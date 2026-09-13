import '../../widgets/operations_panel.dart';
import 'dart:async';
import '../../core/utils/action_feedback.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/operations/announcement.dart';
import '../../services/announcement_service.dart';
import '../../services/realtime_socket_service.dart';
import '../../services/session_controller.dart';

class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({
    super.key,
    required this.realtimeSocketService,
    this.repository,
  });

  final RealtimeSocketService realtimeSocketService;
  final AnnouncementRepository? repository;

  @override
  State<AdminAnnouncementsScreen> createState() =>
      _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  static const _pageSize = 25;
  static const _categories = <String, String>{
    'service_change': 'Service change',
    'disruption': 'Disruption',
    'maintenance': 'Maintenance',
    'safety': 'Safety',
    'general': 'General',
  };
  static const _severities = <String, String>{
    'info': 'Info',
    'warning': 'Warning',
    'critical': 'Critical',
  };

  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _refreshTimer;
  List<AnnouncementModel> _announcements = const [];
  AnnouncementModel? _selected;
  String? _statusFilter;
  String? _audienceFilter;
  String? _categoryFilter;
  String? _severityFilter;
  DateTimeRange? _dateFilter;
  int _page = 1;
  int _total = 0;
  int _totalPages = 0;
  int _loadGeneration = 0;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  AnnouncementRepository get _repository =>
      widget.repository ??
      AnnouncementService(context.read<SessionController>().apiClient);

  @override
  void initState() {
    super.initState();
    _subscription = widget.realtimeSocketService.announcementActivityStream
        .listen((_) => unawaited(_load(silent: true)));
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_load(silent: true)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _loadGeneration++;
    _subscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_loadGeneration;
    final requestedPage = _page;
    if (mounted) {
      setState(() {
        if (silent) {
          _refreshing = true;
        } else {
          _loading = true;
        }
      });
    }

    try {
      final result = await _repository.getAdminAnnouncements(
        page: requestedPage,
        limit: _pageSize,
        status: _statusFilter,
        audience: _audienceFilter,
        category: _categoryFilter,
        severity: _severityFilter,
        from: _dateFilter?.start,
        to: _dateFilter == null
            ? null
            : DateTime(
                _dateFilter!.end.year,
                _dateFilter!.end.month,
                _dateFilter!.end.day,
                23,
                59,
                59,
              ),
      );
      if (!mounted || generation != _loadGeneration) return;

      final selectedId = _selected?.id;
      final selected = result.items.cast<AnnouncementModel?>().firstWhere(
            (item) => item?.id == selectedId,
            orElse: () => result.items.isEmpty ? null : result.items.first,
          );
      setState(() {
        _announcements = result.items;
        _selected = selected;
        _page = result.page;
        _total = result.total;
        _totalPages = result.totalPages;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = ActionFeedback.messageOf(error));
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _applyFilter(VoidCallback update) {
    setState(() {
      update();
      _page = 1;
    });
    unawaited(_load(silent: true));
  }

  Future<void> _changePage(int page) async {
    if (page < 1 || (_totalPages > 0 && page > _totalPages)) return;
    setState(() => _page = page);
    await _load();
  }

  Future<void> _openEditor({
    AnnouncementModel? item,
    bool duplicate = false,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AnnouncementEditorDialog(
        item: item,
        duplicate: duplicate,
        categories: _categories,
        severities: _severities,
        onSave: (body) async {
          if (item == null || duplicate) {
            await _repository.create(body);
          } else {
            await _repository.update(item.id, body);
          }
        },
      ),
    );
    if (changed != true || !mounted) return;
    _showMessage(
      duplicate
          ? 'Announcement duplicated.'
          : item == null
              ? 'Announcement created.'
              : 'Announcement updated.',
    );
    await _load(silent: true);
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              SizedBox(
                width: 120,
                child: FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _archive(AnnouncementModel item) async {
    final now = DateTime.now();
    final isActive = item.status == 'published' &&
        !item.startsAt.isAfter(now) &&
        (item.expiresAt == null || item.expiresAt!.isAfter(now));
    if (isActive &&
        !await _confirm(
          'Archive active announcement?',
          'It will immediately disappear from passenger and driver apps.',
        )) {
      return;
    }

    try {
      await _repository.archive(
        item.id,
        confirmActiveArchive: isActive,
      );
      if (!mounted) return;
      _showMessage('Announcement archived.');
      await _load(silent: true);
    } catch (error) {
      if (mounted) _showMessage(ActionFeedback.messageOf(error));
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showNarrowDetail(AnnouncementModel item) async {
    setState(() => _selected = item);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: _AnnouncementDetail(
            item: item,
            dateLabel: _dateLabel,
            onEdit: _canEdit(item)
                ? () {
                    Navigator.pop(sheetContext);
                    unawaited(_openEditor(item: item));
                  }
                : null,
            onDuplicate: item.status == 'expired'
                ? () {
                    Navigator.pop(sheetContext);
                    unawaited(_openEditor(item: item, duplicate: true));
                  }
                : null,
            onArchive: item.status != 'archived'
                ? () {
                    Navigator.pop(sheetContext);
                    unawaited(_archive(item));
                  }
                : null,
          ),
        ),
      ),
    );
  }

  bool _canEdit(AnnouncementModel item) =>
      item.status == 'scheduled' || item.status == 'published';

  String _dateLabel(DateTime? value) {
    if (value == null) return 'None';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 900;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildFilters(),
              const SizedBox(height: 14),
              Expanded(
                child: Stack(
                  children: [
                    if (desktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 390, child: _buildList(false)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildDetailPane()),
                        ],
                      )
                    else
                      _buildList(true),
                    if (_refreshing)
                      const Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Service announcements',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 3),
            Text(
              'Schedule and publish updates without interrupting operations.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        );
        final action = SizedBox(
          width: compact ? double.infinity : 178,
          child: FilledButton(
            onPressed: () => _openEditor(),
            child: const Text('New announcement'),
          ),
        );
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [title, const SizedBox(height: 12), action])
            : Row(children: [
                Expanded(child: title),
                const SizedBox(width: 12),
                action
              ]);
      },
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filter(
            value: _statusFilter,
            hint: 'All statuses',
            options: const {
              'scheduled': 'Scheduled',
              'published': 'Published',
              'expired': 'Expired',
              'archived': 'Archived',
            },
            onChanged: (value) => _applyFilter(() => _statusFilter = value),
          ),
          const SizedBox(width: 10),
          _filter(
            value: _audienceFilter,
            hint: 'All audiences',
            options: const {
              'PASSENGER': 'Passengers',
              'DRIVER': 'Drivers',
            },
            onChanged: (value) => _applyFilter(() => _audienceFilter = value),
          ),
          const SizedBox(width: 10),
          _filter(
            value: _categoryFilter,
            hint: 'All categories',
            options: _categories,
            onChanged: (value) => _applyFilter(() => _categoryFilter = value),
          ),
          const SizedBox(width: 10),
          _filter(
            value: _severityFilter,
            hint: 'All severities',
            options: _severities,
            onChanged: (value) => _applyFilter(() => _severityFilter = value),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 220,
            height: 56,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 52),
              ),
              onPressed: _pickDateRange,
              child: Text(
                _dateFilter == null
                    ? 'Any date'
                    : '${_dateLabel(_dateFilter!.start).split(' ').first} - '
                        '${_dateLabel(_dateFilter!.end).split(' ').first}',
              ),
            ),
          ),
          if (_dateFilter != null)
            IconButton(
              tooltip: 'Clear date filter',
              onPressed: () => _applyFilter(() => _dateFilter = null),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDateRange: _dateFilter,
    );
    if (range == null || !mounted) return;
    _applyFilter(() => _dateFilter = range);
  }

  Widget _filter({
    required String? value,
    required String hint,
    required Map<String, String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: 174,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$hint:$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: hint),
        items: [
          DropdownMenuItem<String>(value: null, child: Text(hint)),
          for (final entry in options.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildList(bool narrow) {
    return OperationsCard(
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
                    'Announcement history',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '$_total total',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _refreshing ? null : () => _load(silent: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildListBody(narrow)),
          const Divider(height: 1),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildListBody(bool narrow) {
    if (_loading && _announcements.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _announcements.isEmpty) {
      return _CenteredMessage(
        icon: Icons.cloud_off_outlined,
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_announcements.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.campaign_outlined,
        message: 'No announcements match these filters.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: _announcements.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = _announcements[index];
          return _AnnouncementListRow(
            item: item,
            selected: !narrow && _selected?.id == item.id,
            dateLabel: _dateLabel,
            onTap: () {
              if (narrow) {
                unawaited(_showNarrowDetail(item));
              } else {
                setState(() => _selected = item);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildPagination() {
    final shownPage = _totalPages == 0 ? 0 : _page;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: _page > 1 ? () => _changePage(_page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              'Page $shownPage of $_totalPages',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed:
                _page < _totalPages ? () => _changePage(_page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPane() {
    final item = _selected;
    if (item == null) {
      return const OperationsCard(
        margin: EdgeInsets.zero,
        child: _CenteredMessage(
          icon: Icons.article_outlined,
          message: 'Select an announcement to view its full details.',
        ),
      );
    }
    return OperationsCard(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: _AnnouncementDetail(
        item: item,
        dateLabel: _dateLabel,
        onEdit: _canEdit(item) ? () => _openEditor(item: item) : null,
        onDuplicate: item.status == 'expired'
            ? () => _openEditor(item: item, duplicate: true)
            : null,
        onArchive: item.status != 'archived' ? () => _archive(item) : null,
      ),
    );
  }
}

class _AnnouncementListRow extends StatelessWidget {
  const _AnnouncementListRow({
    required this.item,
    required this.selected,
    required this.dateLabel,
    required this.onTap,
  });

  final AnnouncementModel item;
  final bool selected;
  final String Function(DateTime?) dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(item.severity);
    return Material(
      color: selected
          ? const Color(0xFFF0F6F5)
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2),
              top: BorderSide(
                color: selected
                    ? const Color(0xFF9DBCB6)
                    : Colors.black.withValues(alpha: 0.06),
              ),
              right: BorderSide(
                color: selected
                    ? const Color(0xFF9DBCB6)
                    : Colors.black.withValues(alpha: 0.06),
              ),
              bottom: BorderSide(
                color: selected
                    ? const Color(0xFF9DBCB6)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(label: item.status, color: color),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _bodyPreview(item.body),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 9),
              Text(
                '${item.category.replaceAll('_', ' ')}  |  '
                'Rev ${item.revision}  |  ${dateLabel(item.startsAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementDetail extends StatelessWidget {
  const _AnnouncementDetail({
    required this.item,
    required this.dateLabel,
    required this.onEdit,
    required this.onDuplicate,
    required this.onArchive,
  });

  final AnnouncementModel item;
  final String Function(DateTime?) dateLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(item.severity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusPill(label: item.status, color: color),
                    _StatusPill(
                      label: item.category.replaceAll('_', ' '),
                      color: Colors.blueGrey,
                    ),
                    _StatusPill(label: item.severity, color: color),
                    _StatusPill(
                      label: 'revision ${item.revision}',
                      color: Colors.blueGrey,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  item.title,
                  softWrap: true,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 14),
                SelectableText(
                  item.body,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.55,
                      ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                _DetailLine(
                  label: 'Audience',
                  value: item.audiences.join(' + '),
                ),
                _DetailLine(
                  label: 'Starts',
                  value: dateLabel(item.startsAt),
                ),
                _DetailLine(
                  label: 'Expires',
                  value: dateLabel(item.expiresAt),
                ),
                _DetailLine(
                  label: 'Created by',
                  value: item.creatorName?.isNotEmpty == true
                      ? item.creatorName!
                      : 'Admin',
                ),
                _DetailLine(
                  label: 'Last edited by',
                  value: item.lastEditorName?.isNotEmpty == true
                      ? item.lastEditorName!
                      : 'Admin',
                ),
              ],
            ),
          ),
        ),
        if (onEdit != null || onDuplicate != null || onArchive != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
              ),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                if (onDuplicate != null)
                  SizedBox(
                    width: 132,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      onPressed: onDuplicate,
                      child: const Text('Duplicate'),
                    ),
                  ),
                if (onEdit != null)
                  SizedBox(
                    width: 112,
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                if (onArchive != null)
                  SizedBox(
                    width: 120,
                    child: TextButton(
                      onPressed: onArchive,
                      child: const Text('Archive'),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Expanded(child: Text(value, softWrap: true)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.replaceAll('_', ' ').toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, softWrap: true),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: 132,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnnouncementEditorDialog extends StatefulWidget {
  const _AnnouncementEditorDialog({
    required this.item,
    required this.duplicate,
    required this.categories,
    required this.severities,
    required this.onSave,
  });

  final AnnouncementModel? item;
  final bool duplicate;
  final Map<String, String> categories;
  final Map<String, String> severities;
  final Future<void> Function(Map<String, dynamic> body) onSave;

  @override
  State<_AnnouncementEditorDialog> createState() =>
      _AnnouncementEditorDialogState();
}

class _AnnouncementEditorDialogState extends State<_AnnouncementEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late String _category;
  late String _severity;
  late bool _passengers;
  late bool _drivers;
  late bool _publishNow;
  late DateTime _startsAt;
  DateTime? _expiresAt;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.item != null && !widget.duplicate;
  bool get _editingPublished => _editing && widget.item!.status == 'published';

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _titleController = TextEditingController(text: item?.title ?? '');
    _bodyController = TextEditingController(text: item?.body ?? '');
    _category = item?.category ?? 'general';
    _severity = item?.severity ?? 'info';
    _passengers = item?.audiences.contains('PASSENGER') ?? true;
    _drivers = item?.audiences.contains('DRIVER') ?? true;
    _publishNow =
        widget.duplicate || item == null || item.status == 'published';
    _startsAt = widget.duplicate || item == null
        ? DateTime.now()
        : item.startsAt.toLocal();
    _expiresAt = widget.duplicate ? null : item?.expiresAt?.toLocal();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_passengers && !_drivers) {
      setState(() => _error = 'Select at least one audience.');
      return;
    }

    final startsAt = _editingPublished && _publishNow
        ? widget.item!.startsAt
        : _publishNow
            ? DateTime.now()
            : _startsAt;
    if (!_publishNow && !startsAt.isAfter(DateTime.now())) {
      setState(() => _error = 'Scheduled publish time must be in the future.');
      return;
    }
    if (_expiresAt != null && !_expiresAt!.isAfter(startsAt)) {
      setState(() => _error = 'Expiry must be later than the publish time.');
      return;
    }

    var criticalConfirmed = false;
    if (_severity == 'critical') {
      criticalConfirmed = await _confirmCritical();
      if (!criticalConfirmed || !mounted) return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave({
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
        'category': _category,
        'severity': _severity,
        'audiences': [
          if (_passengers) 'PASSENGER',
          if (_drivers) 'DRIVER',
        ],
        'startsAt': startsAt.toUtc().toIso8601String(),
        'expiresAt': _expiresAt?.toUtc().toIso8601String(),
        if (criticalConfirmed) 'confirmCritical': true,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = ActionFeedback.messageOf(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmCritical() async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Publish critical announcement?'),
            content: const Text(
              'This will be prominently shown to the selected audiences.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              SizedBox(
                width: 150,
                child: FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Publish critical'),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return 'None';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.duplicate
                          ? 'Duplicate announcement'
                          : _editing
                              ? 'Edit revision ${widget.item!.revision}'
                              : 'New announcement',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.duplicate)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'A new announcement will be created at revision 1.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      TextFormField(
                        controller: _titleController,
                        maxLength: 160,
                        decoration: const InputDecoration(labelText: 'Title'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Required'
                                : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _bodyController,
                        minLines: 5,
                        maxLines: 10,
                        maxLength: 5000,
                        decoration: const InputDecoration(labelText: 'Message'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Required'
                                : null,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('category:$_category'),
                              initialValue: _category,
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(labelText: 'Category'),
                              items: [
                                for (final entry in widget.categories.entries)
                                  DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _category = value!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('severity:$_severity'),
                              initialValue: _severity,
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(labelText: 'Severity'),
                              items: [
                                for (final entry in widget.severities.entries)
                                  DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _severity = value!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Audience',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Passengers'),
                            selected: _passengers,
                            onSelected: (value) =>
                                setState(() => _passengers = value),
                          ),
                          FilterChip(
                            label: const Text('Drivers'),
                            selected: _drivers,
                            onSelected: (value) =>
                                setState(() => _drivers = value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                            value: true,
                            label: Text(
                              _editingPublished
                                  ? 'Keep published'
                                  : 'Publish now',
                            ),
                          ),
                          const ButtonSegment(
                            value: false,
                            label: Text('Schedule'),
                          ),
                        ],
                        selected: {_publishNow},
                        onSelectionChanged: (value) =>
                            setState(() => _publishNow = value.first),
                      ),
                      if (_editingPublished && _publishNow)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Original start time will be preserved.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (!_publishNow) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await _pickDateTime(_startsAt);
                            if (picked != null) {
                              setState(() => _startsAt = picked);
                            }
                          },
                          icon: const Icon(Icons.schedule),
                          label: Text('Starts ${_dateLabel(_startsAt)}'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final initial = _expiresAt ??
                              DateTime.now().add(const Duration(days: 1));
                          final picked = await _pickDateTime(initial);
                          if (picked != null) {
                            setState(() => _expiresAt = picked);
                          }
                        },
                        icon: const Icon(Icons.event_busy_outlined),
                        label: Text('Expires ${_dateLabel(_expiresAt)}'),
                      ),
                      if (_expiresAt != null)
                        TextButton(
                          onPressed: () => setState(() => _expiresAt = null),
                          child: const Text('Remove expiry'),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          softWrap: true,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 160,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.campaign_outlined),
                      label: Text(_editing ? 'Save revision' : 'Publish'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _severityColor(String severity) {
  return switch (severity) {
    'critical' => const Color(0xFFB42318),
    'warning' => const Color(0xFFB54708),
    _ => const Color(0xFF087A72),
  };
}

String _bodyPreview(String body) {
  final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= 180) return compact;
  return '${compact.substring(0, 177)}...';
}
