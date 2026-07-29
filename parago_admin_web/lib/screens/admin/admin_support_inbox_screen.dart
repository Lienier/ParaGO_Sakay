import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
import '../../models/support/support_message.dart';
import '../../models/support/support_thread.dart';
import '../../services/session_controller.dart';
import '../../services/support_service.dart';
import '../../services/realtime_socket_service.dart';

class AdminSupportInboxScreen extends StatefulWidget {
  const AdminSupportInboxScreen({
    super.key,
    required this.realtimeSocketService,
    this.repository,
  });

  final RealtimeSocketService realtimeSocketService;
  final SupportRepository? repository;

  @override
  State<AdminSupportInboxScreen> createState() =>
      _AdminSupportInboxScreenState();
}

class _AdminSupportInboxScreenState extends State<AdminSupportInboxScreen> {
  final TextEditingController _replyController = TextEditingController();
  final Set<String> _knownThreadIds = <String>{};
  StreamSubscription<Map<String, dynamic>>? _supportSubscription;
  Timer? _refreshTimer;

  List<SupportThreadModel> _threads = const <SupportThreadModel>[];
  List<SupportMessageModel> _messages = const <SupportMessageModel>[];
  SupportThreadModel? _selectedThread;
  bool _loading = true;
  bool _replying = false;
  bool _taking = false;
  String? _error;
  String? _statusFilter;
  String? _categoryFilter;
  String? _userRoleFilter;
  bool _includeClosed = false;
  int _threadListGeneration = 0;
  int _threadDetailGeneration = 0;

  SupportRepository get _service =>
      widget.repository ??
      SupportService(context.read<SessionController>().apiClient);

  static const _statusOptions = [
    ('', 'All statuses'),
    ('open', 'Open'),
    ('awaiting_admin', 'Awaiting admin'),
    ('awaiting_user', 'Awaiting user'),
    ('resolved', 'Resolved'),
    ('closed', 'Closed'),
  ];

  static const _categoryOptions = [
    ('', 'All categories'),
    ('complaint', 'Complaint'),
    ('lost_item', 'Lost item'),
    ('fare_concern', 'Fare concern'),
    ('trip_issue', 'Trip issue'),
    ('safety_concern', 'Safety concern'),
    ('general_help', 'General help'),
  ];

  static const _roleOptions = [
    ('', 'All users'),
    ('PASSENGER', 'Passengers'),
    ('DRIVER', 'Drivers'),
  ];

  @override
  void initState() {
    super.initState();
    _supportSubscription =
        widget.realtimeSocketService.supportActivityStream.listen(
      (event) {
        final notificationType = event['notificationType']?.toString() ?? '';
        if (notificationType == 'support.thread.read') {
          return;
        }
        if (mounted) {
          unawaited(_loadThreads(silent: true));
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadThreads());
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        unawaited(_loadThreads(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _threadListGeneration++;
    _threadDetailGeneration++;
    _refreshTimer?.cancel();
    _replyController.dispose();
    _supportSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadThreads({bool silent = false}) async {
    final generation = ++_threadListGeneration;
    if (!silent && mounted) {
      setState(() => _loading = true);
    }
    try {
      final threads = await _service.getInboxThreads(
        status: _statusFilter,
        category: _categoryFilter,
        userRole: _userRoleFilter,
        includeClosed: _includeClosed,
      );
      if (!mounted || generation != _threadListGeneration) return;
      setState(() {
        _threads = threads;
        _knownThreadIds
          ..clear()
          ..addAll(threads.map((thread) => thread.id));
        _error = null;
      });
      if (_selectedThread != null) {
        final match =
            threads.where((thread) => thread.id == _selectedThread!.id);
        if (match.isEmpty) {
          _selectedThread = threads.isEmpty ? null : threads.first;
        } else {
          _selectedThread = match.first;
        }
      } else if (threads.isNotEmpty) {
        _selectedThread = threads.first;
      }
      if (_selectedThread != null) {
        await _loadThread(_selectedThread!, silent: true);
      } else {
        setState(() => _messages = const <SupportMessageModel>[]);
      }
    } catch (error) {
      if (!mounted || generation != _threadListGeneration) return;
      setState(() => _error = ActionFeedback.messageOf(error));
    } finally {
      if (mounted && generation == _threadListGeneration && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadThread(SupportThreadModel thread,
      {bool silent = false}) async {
    final generation = ++_threadDetailGeneration;
    if (!silent && mounted) {
      setState(() => _loading = true);
    }
    try {
      final data = await _service.getThreadMessages(thread.id);
      final parsedThread =
          SupportThreadModel.fromJson(data['thread'] as Map<String, dynamic>);
      final messages = data['messages'];
      final parsedMessages = messages is List
          ? messages
              .whereType<Map>()
              .map((item) =>
                  SupportMessageModel.fromJson(item.cast<String, dynamic>()))
              .toList(growable: false)
          : const <SupportMessageModel>[];
      if (!mounted || generation != _threadDetailGeneration) return;
      setState(() {
        _selectedThread = parsedThread;
        _messages = parsedMessages;
        _error = null;
      });
      await _service.markRead(parsedThread.id);
    } catch (error) {
      if (!mounted || generation != _threadDetailGeneration) return;
      setState(() => _error = ActionFeedback.messageOf(error));
    } finally {
      if (mounted && generation == _threadDetailGeneration && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _selectThread(SupportThreadModel thread) async {
    setState(() => _selectedThread = thread);
    await _loadThread(thread);
    if (!mounted || MediaQuery.sizeOf(context).width >= 980) return;
    await _showNarrowThreadDetail();
  }

  Future<void> _showNarrowThreadDetail() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final thread = _selectedThread;
          if (thread == null) return const _EmptySupportDetail();
          Future<void> refreshAfter(Future<void> Function() action) async {
            await action();
            if (sheetContext.mounted) setSheetState(() {});
          }

          return SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.9,
              child: _SupportThreadDetail(
                thread: thread,
                messages: _messages,
                loading: _loading,
                replyController: _replyController,
                replying: _replying,
                taking: _taking,
                onReply: () => refreshAfter(_replyToThread),
                onTakeThread: () => refreshAfter(_takeThread),
                onResolve: ({String status = 'resolved'}) =>
                    refreshAfter(() => _resolveThread(status: status)),
                onClose: () => refreshAfter(_closeThread),
                onReopen: () => refreshAfter(_reopenThread),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _takeThread() async {
    final thread = _selectedThread;
    if (thread == null || _taking) return;
    setState(() => _taking = true);
    try {
      final session = context.read<SessionController>();
      final adminId = session.user?.userId ?? session.user?.adminId ?? '';
      if (adminId.isEmpty) {
        throw StateError('Admin profile is unavailable.');
      }
      final updated = await _service.assignThread(
        threadId: thread.id,
        assignedAdminId: adminId,
      );
      if (!mounted) return;
      setState(() {
        _selectedThread = SupportThreadModel.fromJson(updated);
      });
      await _loadThreads(silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ActionFeedback.messageOf(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _taking = false);
      }
    }
  }

  Future<void> _replyToThread() async {
    final thread = _selectedThread;
    final body = _replyController.text.trim();
    if (thread == null || body.isEmpty || _replying) return;

    setState(() => _replying = true);
    try {
      final result = await _service.sendMessage(
        threadId: thread.id,
        body: body,
      );
      _replyController.clear();
      if (!mounted) return;
      setState(() {
        _selectedThread = SupportThreadModel.fromJson(
            result['thread'] as Map<String, dynamic>);
      });
      await _loadThread(_selectedThread!, silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ActionFeedback.messageOf(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _replying = false);
      }
    }
  }

  Future<void> _resolveThread({String status = 'resolved'}) async {
    final thread = _selectedThread;
    if (thread == null) return;
    try {
      final result = await _service.resolveThread(
        threadId: thread.id,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        _selectedThread = SupportThreadModel.fromJson(result);
      });
      await _loadThread(_selectedThread!, silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ActionFeedback.messageOf(error))),
      );
    }
  }

  Future<void> _closeThread() async {
    final thread = _selectedThread;
    if (thread == null) return;
    try {
      final result = await _service.closeThread(thread.id);
      if (!mounted) return;
      setState(() {
        _selectedThread = SupportThreadModel.fromJson(result);
      });
      await _loadThread(_selectedThread!, silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ActionFeedback.messageOf(error))),
      );
    }
  }

  Future<void> _reopenThread() async {
    final thread = _selectedThread;
    if (thread == null) return;
    try {
      final result = await _service.reopenThread(thread.id);
      if (!mounted) return;
      setState(() {
        _selectedThread = SupportThreadModel.fromJson(result);
      });
      await _loadThread(_selectedThread!, silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ActionFeedback.messageOf(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedThread;
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Support inbox',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Review and respond to passenger and driver concerns.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SupportInboxFilters(
            statusFilter: _statusFilter,
            categoryFilter: _categoryFilter,
            userRoleFilter: _userRoleFilter,
            includeClosed: _includeClosed,
            statusOptions: _statusOptions,
            categoryOptions: _categoryOptions,
            roleOptions: _roleOptions,
            onStatusChanged: (value) {
              setState(() => _statusFilter = value);
              unawaited(_loadThreads());
            },
            onCategoryChanged: (value) {
              setState(() => _categoryFilter = value);
              unawaited(_loadThreads());
            },
            onUserRoleChanged: (value) {
              setState(() => _userRoleFilter = value);
              unawaited(_loadThreads());
            },
            onIncludeClosedChanged: (value) {
              setState(() => _includeClosed = value);
              unawaited(_loadThreads());
            },
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 980;
                final inboxPane = _SupportInboxList(
                  threads: _threads,
                  loading: _loading,
                  error: _error,
                  onRefresh: () => _loadThreads(),
                  onSelect: _selectThread,
                  selectedThreadId: selected?.id,
                );
                if (stacked) return inboxPane;

                final detailPane = selected == null
                    ? const _EmptySupportDetail()
                    : _SupportThreadDetail(
                        thread: selected,
                        messages: _messages,
                        loading: _loading,
                        replyController: _replyController,
                        replying: _replying,
                        taking: _taking,
                        onReply: _replyToThread,
                        onTakeThread: _takeThread,
                        onResolve: _resolveThread,
                        onClose: _closeThread,
                        onReopen: _reopenThread,
                      );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 390, child: inboxPane),
                    const SizedBox(width: 16),
                    Expanded(child: detailPane),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportInboxFilters extends StatelessWidget {
  const _SupportInboxFilters({
    required this.statusFilter,
    required this.categoryFilter,
    required this.userRoleFilter,
    required this.includeClosed,
    required this.statusOptions,
    required this.categoryOptions,
    required this.roleOptions,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onUserRoleChanged,
    required this.onIncludeClosedChanged,
  });

  final String? statusFilter;
  final String? categoryFilter;
  final String? userRoleFilter;
  final bool includeClosed;
  final List<(String, String)> statusOptions;
  final List<(String, String)> categoryOptions;
  final List<(String, String)> roleOptions;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onUserRoleChanged;
  final ValueChanged<bool> onIncludeClosedChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _SupportFilterDropdown(
            label: 'Status',
            value: statusFilter,
            options: statusOptions,
            onChanged: onStatusChanged,
          ),
          const SizedBox(width: 10),
          _SupportFilterDropdown(
            label: 'Category',
            value: categoryFilter,
            options: categoryOptions,
            onChanged: onCategoryChanged,
          ),
          const SizedBox(width: 10),
          _SupportFilterDropdown(
            label: 'User role',
            value: userRoleFilter,
            options: roleOptions,
            onChanged: onUserRoleChanged,
          ),
          const SizedBox(width: 12),
          FilterChip(
            selected: includeClosed,
            label: const Text('Include closed'),
            onSelected: onIncludeClosedChanged,
          ),
        ],
      ),
    );
  }
}

class _SupportFilterDropdown extends StatelessWidget {
  const _SupportFilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<(String, String)> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label:$value'),
        initialValue: value ?? '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final entry in options)
            DropdownMenuItem(
              value: entry.$1,
              child: Text(entry.$2, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (next) => onChanged(next?.isEmpty == true ? null : next),
      ),
    );
  }
}

class _SupportInboxList extends StatelessWidget {
  const _SupportInboxList({
    required this.threads,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onSelect,
    required this.selectedThreadId,
  });

  final List<SupportThreadModel> threads;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final ValueChanged<SupportThreadModel> onSelect;
  final String? selectedThreadId;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Conversation queue',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${threads.length} threads',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: loading ? null : () => onRefresh(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: _SupportNotice(message: error!),
            ),
          Expanded(
            child: threads.isEmpty
                ? const _EmptyInboxState()
                : RefreshIndicator(
                    onRefresh: onRefresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(10),
                      itemCount: threads.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final thread = threads[index];
                        return _InboxThreadTile(
                          thread: thread,
                          selected: selectedThreadId == thread.id,
                          onTap: () => onSelect(thread),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _InboxThreadTile extends StatelessWidget {
  const _InboxThreadTile({
    required this.thread,
    required this.selected,
    required this.onTap,
  });

  final SupportThreadModel thread;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = thread.unreadAdminCount;
    final accent = _supportThreadAccent(thread);
    return Material(
      color:
          selected ? accent.withValues(alpha: 0.09) : const Color(0xFFF8FAFB),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accent, width: 5),
              top: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
              right: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
              bottom: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      thread.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  if (unread > 0)
                    _Pill(label: '$unread unread', accent: accent),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${thread.threadLabel} | ${thread.userRole.toLowerCase()}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF5C6561),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                thread.lastMessagePreview?.trim().isNotEmpty == true
                    ? thread.lastMessagePreview!.trim()
                    : 'No messages yet.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportThreadDetail extends StatelessWidget {
  const _SupportThreadDetail({
    required this.thread,
    required this.messages,
    required this.loading,
    required this.replyController,
    required this.replying,
    required this.taking,
    required this.onReply,
    required this.onTakeThread,
    required this.onResolve,
    required this.onClose,
    required this.onReopen,
  });

  final SupportThreadModel thread;
  final List<SupportMessageModel> messages;
  final bool loading;
  final TextEditingController replyController;
  final bool replying;
  final bool taking;
  final Future<void> Function() onReply;
  final Future<void> Function() onTakeThread;
  final Future<void> Function({String status}) onResolve;
  final Future<void> Function() onClose;
  final Future<void> Function() onReopen;

  @override
  Widget build(BuildContext context) {
    final closed = thread.status == 'closed';
    final selected = thread;
    final accent = _supportThreadAccent(thread);
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          selected.title,
          softWrap: true,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _Pill(label: selected.status, accent: accent),
            _Pill(
              label: selected.category.replaceAll('_', ' '),
              accent: Colors.blueGrey,
            ),
            _Pill(
              label: selected.userRole.toLowerCase(),
              accent: Colors.blueGrey,
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          selected.creatorName ?? 'Unknown user',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF5C6561),
              ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        SizedBox(
          width: 124,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),
            onPressed: taking ? null : onTakeThread,
            child: const Text('Take thread'),
          ),
        ),
        if (closed)
          SizedBox(
            width: 100,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
              ),
              onPressed: onReopen,
              child: const Text('Reopen'),
            ),
          )
        else ...[
          SizedBox(
            width: 100,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
              ),
              onPressed: () => onResolve(status: 'resolved'),
              child: const Text('Resolve'),
            ),
          ),
          SizedBox(
            width: 84,
            child: TextButton(
              onPressed: onClose,
              child: const Text('Close'),
            ),
          ),
        ],
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(height: 6, color: accent),
          Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 700) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      identity,
                      const SizedBox(height: 14),
                      actions,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: actions,
                    ),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text('No messages in this conversation yet.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(18),
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final mine = message.senderRole == 'ADMIN';
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 600),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: mine
                                ? const Color(0xFFEAF5F2)
                                : const Color(0xFFF4F5F7),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: mine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Text(
                                mine ? 'Admin' : (message.senderName ?? 'User'),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _wrapLongTokens(message.body),
                                softWrap: true,
                              ),
                              if ((message.createdAt ?? '').isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  message.createdAt!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF68716C),
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: messages.length,
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: replyController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: closed
                            ? 'Reopen the thread to reply'
                            : 'Type reply',
                        border: const OutlineInputBorder(),
                        enabled: !closed,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 88,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(88, 52),
                      ),
                      onPressed: closed || replying ? null : onReply,
                      child: const Text('Reply'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySupportDetail extends StatelessWidget {
  const _EmptySupportDetail();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Text(
            'Select a support thread to review messages and respond.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF5C6561),
                ),
          ),
        ),
      ),
    );
  }
}

class _EmptyInboxState extends StatelessWidget {
  const _EmptyInboxState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'No support threads match the current filters.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF5C6561),
            ),
      ),
    );
  }
}

class _SupportNotice extends StatelessWidget {
  const _SupportNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0D7A0)),
      ),
      child: Text(message),
    );
  }
}

String _wrapLongTokens(String value, {int chunkSize = 28}) {
  final longTokenPattern = RegExp('\\S{${chunkSize + 1},}');
  return value.replaceAllMapped(longTokenPattern, (match) {
    final token = match.group(0)!;
    final buffer = StringBuffer();
    for (var index = 0; index < token.length; index += chunkSize) {
      final end =
          (index + chunkSize < token.length) ? index + chunkSize : token.length;
      buffer.write(token.substring(index, end));
      if (end < token.length) {
        buffer.write('\u200B');
      }
    }
    return buffer.toString();
  });
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

Color _supportThreadAccent(SupportThreadModel thread) {
  if (thread.unreadAdminCount > 0 || thread.status == 'awaiting_admin') {
    return const Color(0xFFB54708);
  }
  if (thread.status == 'closed' || thread.status == 'resolved') {
    return const Color(0xFF667085);
  }
  return const Color(0xFF087A72);
}
