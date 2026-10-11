import '../../widgets/glass_surface.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
import '../../models/support/support_message.dart';
import '../../models/support/support_thread.dart';
import '../../services/realtime_socket_service.dart';
import '../../services/session_controller.dart';
import '../../services/support_service.dart';

class DriverSupportScreen extends StatefulWidget {
  const DriverSupportScreen({
    super.key,
    this.routeId,
    this.tripSessionId,
    this.initialCategory,
    this.initialSubject,
    this.initialMessage,
    required this.realtimeSocketService,
  });

  final String? routeId;
  final String? tripSessionId;
  final String? initialCategory;
  final String? initialSubject;
  final String? initialMessage;
  final RealtimeSocketService realtimeSocketService;

  @override
  State<DriverSupportScreen> createState() => _DriverSupportScreenState();
}

class _DriverSupportScreenState extends State<DriverSupportScreen> {
  final Set<String> _knownThreadIds = <String>{};
  StreamSubscription<Map<String, dynamic>>? _supportSubscription;
  Timer? _refreshTimer;
  List<SupportThreadModel> _threads = const <SupportThreadModel>[];
  bool _loading = true;
  bool _creating = false;
  bool _threadsRequestInFlight = false;
  bool _threadsRefreshPending = false;
  int _threadListGeneration = 0;
  String? _message;

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
    _refreshTimer?.cancel();
    _supportSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadThreads({bool silent = false}) async {
    if (_threadsRequestInFlight) {
      _threadsRefreshPending = true;
      return;
    }
    _threadsRequestInFlight = true;
    final generation = ++_threadListGeneration;
    if (!silent && mounted) {
      setState(() => _loading = true);
    }

    try {
      final session = context.read<SessionController>();
      final threads = await SupportService(session.apiClient).getMyThreads();
      if (!mounted || generation != _threadListGeneration) return;
      setState(() {
        _threads = threads;
        _knownThreadIds
          ..clear()
          ..addAll(threads.map((thread) => thread.id));
        _message = null;
      });
    } catch (error) {
      if (!mounted || generation != _threadListGeneration) return;
      setState(() => _message = ActionFeedback.messageOf(error));
    } finally {
      _threadsRequestInFlight = false;
      if (mounted && generation == _threadListGeneration && !silent) {
        setState(() => _loading = false);
      }
      if (mounted && _threadsRefreshPending) {
        _threadsRefreshPending = false;
        unawaited(_loadThreads(silent: true));
      }
    }
  }

  Future<void> _openThreadComposer() async {
    final created = await showGlassBottomSheet<_SupportThreadDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _SupportThreadComposer(
        initialCategory: widget.initialCategory,
        initialSubject: widget.initialSubject,
        initialMessage: widget.initialMessage,
      ),
    );

    if (!mounted || created == null) {
      return;
    }

    setState(() => _creating = true);
    try {
      final session = context.read<SessionController>();
      final response = await SupportService(session.apiClient).createThread(
        subject: created.subject,
        category: created.category,
        message: created.message,
        tripSessionId: widget.tripSessionId,
        routeId: widget.routeId,
      );
      final thread = SupportThreadModel.fromJson(
          response['thread'] as Map<String, dynamic>);
      if (!mounted) return;
      await _loadThreads(silent: true);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DriverSupportThreadScreen(
            thread: thread,
            realtimeSocketService: widget.realtimeSocketService,
          ),
        ),
      );
      if (mounted) {
        await _loadThreads(silent: true);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(ActionFeedback.messageOf(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<void> _openThread(SupportThreadModel thread) async {
    final updated = await Navigator.of(context).push<SupportThreadModel>(
      MaterialPageRoute(
        builder: (_) => DriverSupportThreadScreen(
          thread: thread,
          realtimeSocketService: widget.realtimeSocketService,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _threads = _upsertThread(_threads, updated);
      });
      return;
    }
    await _loadThreads(silent: true);
  }

  List<SupportThreadModel> _upsertThread(
    List<SupportThreadModel> threads,
    SupportThreadModel thread,
  ) {
    final next = List<SupportThreadModel>.from(threads);
    final index = next.indexWhere((item) => item.id == thread.id);
    if (index >= 0) {
      next[index] = thread;
    } else {
      next.insert(0, thread);
    }
    next.sort(
      (left, right) => (right.lastMessageAt ?? right.createdAt ?? '').compareTo(
        left.lastMessageAt ?? left.createdAt ?? '',
      ),
    );
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final threads = _threads;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _loadThreads(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating ? null : _openThreadComposer,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New thread'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadThreads,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            _SupportHeaderCard(
              title: 'Chat with ParaGO support',
              subtitle:
                  'Send complaints, trip concerns, or general help requests to the admin team.',
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              _SupportNotice(message: _message!),
            ],
            const SizedBox(height: 16),
            if (_loading)
              const LinearProgressIndicator()
            else if (threads.isEmpty)
              const _EmptySupportState()
            else
              for (final thread in threads) ...[
                _SupportThreadTile(
                  thread: thread,
                  onTap: () => _openThread(thread),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class DriverSupportThreadScreen extends StatefulWidget {
  const DriverSupportThreadScreen({
    super.key,
    required this.thread,
    required this.realtimeSocketService,
    this.supportService,
  });

  final SupportThreadModel thread;
  final RealtimeSocketService realtimeSocketService;
  final SupportService? supportService;

  @override
  State<DriverSupportThreadScreen> createState() =>
      _DriverSupportThreadScreenState();
}

class _DriverSupportThreadScreenState extends State<DriverSupportThreadScreen> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _supportSubscription;
  Timer? _refreshTimer;
  SupportThreadModel? _thread;
  List<SupportMessageModel> _messages = const <SupportMessageModel>[];
  bool _loading = true;
  bool _sending = false;
  bool _threadRequestInFlight = false;
  bool _threadRefreshPending = false;
  int _threadDetailGeneration = 0;
  String? _message;

  SupportService get _supportService =>
      widget.supportService ??
      SupportService(context.read<SessionController>().apiClient);

  @override
  void initState() {
    super.initState();
    _thread = widget.thread;
    _supportSubscription =
        widget.realtimeSocketService.supportActivityStream.listen(
      (event) {
        final notificationType = event['notificationType']?.toString() ?? '';
        if (notificationType == 'support.thread.read') {
          return;
        }
        final threadId =
            (event['threadId'] ?? event['id'] ?? event['_id'])?.toString() ??
                '';
        if (threadId.isNotEmpty && _thread?.id == threadId && mounted) {
          unawaited(_loadThread(silent: true));
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadThread());
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        unawaited(_loadThread(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _threadDetailGeneration++;
    _refreshTimer?.cancel();
    _composerController.dispose();
    _messageScrollController.dispose();
    _supportSubscription?.cancel();
    super.dispose();
  }

  void _scrollToLatestMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_messageScrollController.hasClients) {
        return;
      }
      _messageScrollController.jumpTo(
        _messageScrollController.position.maxScrollExtent,
      );
    });
  }

  Future<void> _loadThread({bool silent = false}) async {
    if (_threadRequestInFlight) {
      _threadRefreshPending = true;
      return;
    }
    _threadRequestInFlight = true;
    final generation = ++_threadDetailGeneration;
    if (!silent && mounted) {
      setState(() => _loading = true);
    }
    try {
      final data = await _supportService.getThreadMessages(_thread!.id);
      final thread = SupportThreadModel.fromJson(
        data['thread'] as Map<String, dynamic>,
      );
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
        _thread = thread;
        _messages = parsedMessages;
        _message = null;
      });
      _scrollToLatestMessage();
      await _supportService.markRead(thread.id);
    } catch (error) {
      if (!mounted || generation != _threadDetailGeneration) return;
      setState(() => _message = ActionFeedback.messageOf(error));
    } finally {
      _threadRequestInFlight = false;
      if (mounted && generation == _threadDetailGeneration && !silent) {
        setState(() => _loading = false);
      }
      if (mounted && _threadRefreshPending) {
        _threadRefreshPending = false;
        unawaited(_loadThread(silent: true));
      }
    }
  }

  Future<void> _sendMessage() async {
    final body = _composerController.text.trim();
    if (body.isEmpty || _sending || _thread == null) {
      return;
    }

    setState(() => _sending = true);
    try {
      final result = await _supportService.sendMessage(
        threadId: _thread!.id,
        body: body,
      );
      final thread = SupportThreadModel.fromJson(
        result['thread'] as Map<String, dynamic>,
      );
      if (!mounted) return;
      _composerController.clear();
      setState(() {
        _thread = thread;
      });
      await _loadThread(silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(ActionFeedback.messageOf(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _reopenThread() async {
    final thread = _thread;
    if (thread == null) return;
    try {
      final result = await _supportService.reopenThread(thread.id);
      if (!mounted) return;
      setState(() {
        _thread = SupportThreadModel.fromJson(result);
      });
      await _loadThread(silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(ActionFeedback.messageOf(error))),
      );
    }
  }

  Future<void> _closeThread() async {
    final thread = _thread;
    if (thread == null) return;
    try {
      final result = await _supportService.closeThread(thread.id);
      if (!mounted) return;
      setState(() {
        _thread = SupportThreadModel.fromJson(result);
      });
      await _loadThread(silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        GlassSnackBar(content: Text(ActionFeedback.messageOf(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = _thread!;
    final closed = thread.status == 'closed';
    return Scaffold(
      appBar: AppBar(
        title: Text(thread.title),
        actions: [
          if (closed)
            TextButton(
              onPressed: _reopenThread,
              child: const Text('Reopen'),
            )
          else
            TextButton(
              onPressed: _closeThread,
              child: const Text('Close'),
            ),
        ],
      ),
      body: CustomScrollView(
        controller: _messageScrollController,
        primary: false,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: _ThreadSummaryCard(thread: thread),
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(child: LinearProgressIndicator()),
          if (_message != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SupportNotice(message: _message!),
              ),
            ),
          if (_messages.isEmpty && !_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No messages yet.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, itemIndex) {
                    if (itemIndex.isOdd) {
                      return const SizedBox(height: 10);
                    }
                    final message = _messages[itemIndex ~/ 2];
                    final mine = message.senderRole == 'DRIVER';
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 460),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: mine
                              ? const Color(0xFFDDF1EB)
                              : const Color(0xFFF4F5F7),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: mine
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(
                              mine ? 'You' : (message.senderName ?? 'Admin'),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              message.body,
                              softWrap: true,
                              overflow: TextOverflow.visible,
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
                  childCount:
                      _messages.isEmpty ? 0 : (_messages.length * 2) - 1,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: closed
          ? const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _SupportNotice(
                  message:
                      'This thread is closed. Reopen it to send another message.',
                ),
              ),
            )
          : SafeArea(
              top: false,
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _composerController,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'Type your message',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        tooltip: 'Send message',
                        onPressed: _sending ? null : _sendMessage,
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _SupportThreadDraft {
  const _SupportThreadDraft({
    required this.category,
    required this.message,
    this.subject,
  });

  final String category;
  final String message;
  final String? subject;
}

class _SupportThreadComposer extends StatefulWidget {
  const _SupportThreadComposer({
    required this.initialCategory,
    required this.initialSubject,
    required this.initialMessage,
  });

  final String? initialCategory;
  final String? initialSubject;
  final String? initialMessage;

  @override
  State<_SupportThreadComposer> createState() => _SupportThreadComposerState();
}

class _SupportThreadComposerState extends State<_SupportThreadComposer> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String _category = 'general_help';

  static const _categories = [
    ('complaint', 'Complaint'),
    ('lost_item', 'Lost item'),
    ('fare_concern', 'Fare concern'),
    ('trip_issue', 'Trip issue'),
    ('safety_concern', 'Safety concern'),
    ('general_help', 'General help'),
  ];

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? _category;
    _subjectController.text = widget.initialSubject ?? '';
    _messageController.text = widget.initialMessage ?? '';
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Start a support chat',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tell the admin team what happened and they will reply in the same thread.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF67726E),
                    ),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final entry in _categories)
                    DropdownMenuItem<String>(
                      value: entry.$1,
                      child: Text(entry.$2),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _subjectController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Subject (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _messageController,
                maxLines: 5,
                minLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final body = _messageController.text.trim();
                    if (body.isEmpty) return;
                    Navigator.of(context).pop(
                      _SupportThreadDraft(
                        category: _category,
                        subject: _subjectController.text.trim().isEmpty
                            ? null
                            : _subjectController.text.trim(),
                        message: body,
                      ),
                    );
                  },
                  child: const Text('Create thread'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportHeaderCard extends StatelessWidget {
  const _SupportHeaderCard({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F6A5F), Color(0xFF2157A5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportThreadTile extends StatelessWidget {
  const _SupportThreadTile({
    required this.thread,
    required this.onTap,
  });

  final SupportThreadModel thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = thread.unreadUserCount + thread.unreadAdminCount;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5F2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.forum_outlined,
                  color: Color(0xFF0F6A5F),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        _Pill(label: thread.status.replaceAll('_', ' ')),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      thread.lastMessagePreview?.trim().isNotEmpty == true
                          ? thread.lastMessagePreview!.trim()
                          : 'No messages yet.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF48524D),
                          ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (thread.creatorName?.isNotEmpty == true)
                          _Pill(label: thread.creatorName!),
                        _Pill(label: thread.category.replaceAll('_', ' ')),
                        if (unread > 0) _Pill(label: '$unread unread'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadSummaryCard extends StatelessWidget {
  const _ThreadSummaryCard({required this.thread});

  final SupportThreadModel thread;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _Pill(label: thread.status.replaceAll('_', ' ')),
      _Pill(label: thread.category.replaceAll('_', ' ')),
      if (thread.tripSessionId?.isNotEmpty == true)
        _Pill(label: 'Trip ${thread.tripSessionId}'),
      if (thread.routeId?.isNotEmpty == true)
        _Pill(label: 'Route ${thread.routeId}'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E6E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            thread.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            thread.creatorName?.isNotEmpty == true
                ? '${thread.creatorName}  ·  ${thread.threadLabel}'
                : thread.threadLabel,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5C6561),
                ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0D7A0)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF7A5B15),
            ),
      ),
    );
  }
}

class _EmptySupportState extends StatelessWidget {
  const _EmptySupportState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E6E3)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.support_agent_rounded,
            size: 42,
            color: Color(0xFF0F6A5F),
          ),
          const SizedBox(height: 12),
          Text(
            'No support threads yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Open a new thread whenever you need help with a trip, fare, or passenger concern.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5C6561),
                ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5F2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF0F6A5F),
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
