import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
import '../../models/support/support_message.dart';
import '../../models/support/support_thread.dart';
import '../../services/realtime_socket_service.dart';
import '../../services/session_controller.dart';
import '../../services/support_service.dart';

class PassengerSupportScreen extends StatefulWidget {
  const PassengerSupportScreen({
    super.key,
    this.routeId,
    this.tripSessionId,
    this.pickupRequestId,
    this.rideSessionId,
    this.initialCategory,
    this.initialSubject,
    this.initialMessage,
    this.supportService,
    required this.realtimeSocketService,
  });

  final String? routeId;
  final String? tripSessionId;
  final String? pickupRequestId;
  final String? rideSessionId;
  final String? initialCategory;
  final String? initialSubject;
  final String? initialMessage;
  final SupportService? supportService;
  final RealtimeSocketService realtimeSocketService;

  @override
  State<PassengerSupportScreen> createState() => _PassengerSupportScreenState();
}

class _PassengerSupportScreenState extends State<PassengerSupportScreen> {
  final Set<String> _knownThreadIds = <String>{};
  StreamSubscription<Map<String, dynamic>>? _supportSubscription;
  List<SupportThreadModel> _threads = const <SupportThreadModel>[];
  bool _loading = true;
  bool _creating = false;
  String? _message;

  SupportService get _supportService =>
      widget.supportService ??
      SupportService(context.read<SessionController>().apiClient);

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
  }

  @override
  void dispose() {
    _supportSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadThreads({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loading = true);
    }

    try {
      final threads = await _supportService.getMyThreads();
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _knownThreadIds
          ..clear()
          ..addAll(threads.map((thread) => thread.id));
        _message = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = ActionFeedback.messageOf(error));
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openThreadComposer() async {
    final created = await showModalBottomSheet<_SupportThreadDraft>(
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
      final supportService = _supportService;
      final hasOwnedRideContext =
          (widget.pickupRequestId ?? '').trim().isNotEmpty ||
              (widget.rideSessionId ?? '').trim().isNotEmpty;
      final response = await supportService.createThread(
        subject: created.subject,
        category: created.category,
        message: created.message,
        // A selected live jeep is not proof that this passenger owns its trip.
        tripSessionId: hasOwnedRideContext ? widget.tripSessionId : null,
        pickupRequestId: widget.pickupRequestId,
        rideSessionId: widget.rideSessionId,
        routeId: widget.routeId,
      );
      final thread = SupportThreadModel.fromJson(
          response['thread'] as Map<String, dynamic>);
      if (!mounted) return;
      await _loadThreads(silent: true);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PassengerSupportThreadScreen(
            thread: thread,
            realtimeSocketService: widget.realtimeSocketService,
            supportService: supportService,
          ),
        ),
      );
      if (mounted) {
        await _loadThreads(silent: true);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ActionFeedback.messageOf(error))),
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
        builder: (_) => PassengerSupportThreadScreen(
          thread: thread,
          realtimeSocketService: widget.realtimeSocketService,
          supportService: _supportService,
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
    next.sort((left, right) =>
        (right.lastMessageAt ?? right.createdAt ?? '').compareTo(
          left.lastMessageAt ?? left.createdAt ?? '',
        ));
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
                  'Send complaints, fare concerns, trip issues, or general help requests to the admin team.',
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

class PassengerSupportThreadScreen extends StatefulWidget {
  const PassengerSupportThreadScreen({
    super.key,
    required this.thread,
    required this.realtimeSocketService,
    this.supportService,
  });

  final SupportThreadModel thread;
  final RealtimeSocketService realtimeSocketService;
  final SupportService? supportService;

  @override
  State<PassengerSupportThreadScreen> createState() =>
      _PassengerSupportThreadScreenState();
}

class _PassengerSupportThreadScreenState
    extends State<PassengerSupportThreadScreen> {
  final TextEditingController _composerController = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _supportSubscription;
  SupportThreadModel? _thread;
  List<SupportMessageModel> _messages = const <SupportMessageModel>[];
  bool _loading = true;
  bool _sending = false;
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
        final threadId = event['threadId']?.toString() ?? '';
        if (threadId.isNotEmpty && _thread?.id == threadId && mounted) {
          unawaited(_loadThread(silent: true));
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadThread());
    });
  }

  @override
  void dispose() {
    _composerController.dispose();
    _supportSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadThread({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loading = true);
    }
    try {
      final data = await _supportService.getThreadMessages(_thread!.id);
      final thread =
          SupportThreadModel.fromJson(data['thread'] as Map<String, dynamic>);
      final messages = data['messages'];
      final parsedMessages = messages is List
          ? messages
              .whereType<Map>()
              .map((item) =>
                  SupportMessageModel.fromJson(item.cast<String, dynamic>()))
              .toList(growable: false)
          : const <SupportMessageModel>[];
      if (!mounted) return;
      setState(() {
        _thread = thread;
        _messages = parsedMessages;
        _message = null;
      });
      await _supportService.markRead(thread.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = ActionFeedback.messageOf(error));
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
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
      final thread =
          SupportThreadModel.fromJson(result['thread'] as Map<String, dynamic>);
      if (!mounted) return;
      _composerController.clear();
      setState(() {
        _thread = thread;
      });
      await _loadThread(silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ActionFeedback.messageOf(error))),
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
        SnackBar(content: Text(ActionFeedback.messageOf(error))),
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
        SnackBar(content: Text(ActionFeedback.messageOf(error))),
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
      body: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: _ThreadSummaryCard(thread: thread),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SupportNotice(message: _message!),
            ),
          Expanded(
            child: ListView.separated(
              reverse: false,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemBuilder: (context, index) {
                final message = _messages[index];
                final mine = message.senderRole == 'PASSENGER';
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
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
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
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
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
              itemCount: _messages.length,
            ),
          ),
          if (!closed)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
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
            )
          else
            const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _SupportNotice(
                  message:
                      'This thread is closed. Reopen it to send another message.',
                ),
              ),
            ),
        ],
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
    this.initialCategory,
    this.initialSubject,
    this.initialMessage,
  });

  final String? initialCategory;
  final String? initialSubject;
  final String? initialMessage;

  @override
  State<_SupportThreadComposer> createState() => _SupportThreadComposerState();
}

class _SupportThreadComposerState extends State<_SupportThreadComposer> {
  static const _categories = [
    'general_help',
    'complaint',
    'fare_concern',
    'trip_issue',
    'lost_item',
    'safety_concern',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;
  String _category = 'general_help';

  @override
  void initState() {
    super.initState();
    _subjectController =
        TextEditingController(text: widget.initialSubject ?? '');
    _messageController =
        TextEditingController(text: widget.initialMessage ?? '');
    final initialCategory = widget.initialCategory?.trim().toLowerCase();
    if (initialCategory != null && _categories.contains(initialCategory)) {
      _category = initialCategory;
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          top: 8,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New support thread',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'general_help', child: Text('General help')),
                  DropdownMenuItem(
                      value: 'complaint', child: Text('Complaint')),
                  DropdownMenuItem(
                      value: 'fare_concern', child: Text('Fare concern')),
                  DropdownMenuItem(
                      value: 'trip_issue', child: Text('Trip issue')),
                  DropdownMenuItem(
                      value: 'lost_item', child: Text('Lost item')),
                  DropdownMenuItem(
                      value: 'safety_concern', child: Text('Safety concern')),
                ],
                onChanged: (value) {
                  setState(() => _category = value ?? 'general_help');
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Write your message';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (!_formKey.currentState!.validate()) {
                          return;
                        }
                        Navigator.of(context).pop(
                          _SupportThreadDraft(
                            category: _category,
                            subject: _subjectController.text.trim(),
                            message: _messageController.text.trim(),
                          ),
                        );
                      },
                      child: const Text('Send'),
                    ),
                  ),
                ],
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
        color: const Color(0xFFEAF5F2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5A6561),
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
    return Card(
      elevation: 0,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF0F6A5F).withValues(alpha: 0.12),
          child: Icon(
            _categoryIcon(thread.category),
            color: const Color(0xFF0F6A5F),
          ),
        ),
        title: Text(
          thread.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            thread.threadLabel,
            thread.lastMessagePreview ?? 'No messages yet',
          ].join(' - '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: unread > 0
            ? CircleAvatar(
                radius: 13,
                backgroundColor: const Color(0xFF0F6A5F),
                child: Text(
                  unread.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _ThreadSummaryCard extends StatelessWidget {
  const _ThreadSummaryCard({required this.thread});

  final SupportThreadModel thread;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E7E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(label: thread.category.replaceAll('_', ' ')),
              _Pill(label: thread.status.replaceAll('_', ' ')),
              if ((thread.routeId ?? '').isNotEmpty)
                _Pill(label: 'Route linked'),
              if ((thread.tripSessionId ?? '').isNotEmpty)
                _Pill(label: 'Trip linked'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            thread.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              if ((thread.creatorName ?? '').isNotEmpty) thread.creatorName!,
              if ((thread.creatorEmail ?? '').isNotEmpty) thread.creatorEmail!,
            ].join(' | '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF66706B),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
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
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message),
    );
  }
}

class _EmptySupportState extends StatelessWidget {
  const _EmptySupportState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        children: [
          Icon(
            Icons.support_agent_rounded,
            size: 72,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'No support threads yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start a thread when you need help with a complaint, fare issue, or trip concern.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

IconData _categoryIcon(String category) {
  switch (category) {
    case 'complaint':
      return Icons.report_problem_outlined;
    case 'lost_item':
      return Icons.inventory_2_outlined;
    case 'fare_concern':
      return Icons.payments_outlined;
    case 'trip_issue':
      return Icons.route_outlined;
    case 'safety_concern':
      return Icons.shield_outlined;
    default:
      return Icons.support_agent_rounded;
  }
}
