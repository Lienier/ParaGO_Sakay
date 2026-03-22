import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/parago_format.dart';
import '../../models/operations/notification.dart';
import '../../models/operations/pickup_request.dart';
import '../../models/operations/ride_session.dart';
import '../../models/transport/route_summary.dart';
import '../../models/trip/trip_session.dart';
import '../../services/notification_service.dart';
import '../../services/passenger_service.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';
import '../../services/stop_alert_service.dart';
import '../../services/trip_service.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/status_badge.dart';

class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({super.key});

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  List<TripSession> _trips = [];
  List<RouteSummaryModel> _routes = [];
  List<PickupRequestModel> _requests = [];
  List<RideSessionModel> _rides = [];
  List<NotificationModel> _notifications = [];
  String? _selectedTripId;
  String? _selectedRouteId;
  bool _loading = false;
  String? _statusMessage;

  TripSession? get _selectedTrip {
    for (final trip in _trips) {
      if (trip.id == _selectedTripId) return trip;
    }
    return _trips.isEmpty ? null : _trips.first;
  }

  RideSessionModel? get _activeRide {
    for (final ride in _rides) {
      if (ride.status == 'onboard' || ride.status == 'waiting') {
        return ride;
      }
    }
    return null;
  }

  Future<void> _load() async {
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    final passengerService = PassengerService(session.apiClient);
    final notificationService = NotificationService(session.apiClient);
    final routeService = RouteService(session.apiClient);

    setState(() => _loading = true);

    try {
      final results = await Future.wait<dynamic>([
        tripService.getActiveTrips(),
        passengerService.getMyPickupRequests(),
        passengerService.getMyRides(),
        notificationService.getMine(),
        routeService.getRoutes(),
      ]);

      final trips = results[0] as List<TripSession>;
      final requests = results[1] as List<PickupRequestModel>;
      final rides = results[2] as List<RideSessionModel>;
      final notifications = results[3] as List<NotificationModel>;
      final routes = results[4] as List<RouteSummaryModel>;

      final matchingTripStillExists =
          trips.any((trip) => trip.id == _selectedTripId);
      final nextTripId = matchingTripStillExists
          ? _selectedTripId
          : (trips.isNotEmpty ? trips.first.id : null);
      final nextRouteId = nextTripId == null
          ? null
          : trips.firstWhere((trip) => trip.id == nextTripId).routeId;

      if (!mounted) return;
      setState(() {
        _trips = trips;
        _requests = requests;
        _rides = rides;
        _notifications = notifications;
        _routes = routes;
        _selectedTripId = nextTripId;
        _selectedRouteId = nextRouteId;
      });
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendPickup() async {
    if (_selectedTripId == null || _selectedRouteId == null) {
      setState(() => _statusMessage =
          'Choose an active trip before sending a pickup request.');
      return;
    }

    final payload = await _showPickupDialog();
    if (payload == null) return;
    if (!mounted) return;

    final session = context.read<SessionController>();
    final passengerService = PassengerService(session.apiClient);
    setState(() => _loading = true);

    try {
      final request = await passengerService.createPickupRequest(
        tripSessionId: _selectedTripId!,
        routeId: _selectedRouteId!,
        stopRef: payload.stopRef,
        sourceNote: payload.note,
      );
      setState(() {
        _statusMessage =
            'Pickup request sent for ${request.stopRef ?? 'your stop'}.';
      });
      await _load();
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _board() async {
    final pending = _requests
        .where((request) =>
            request.status == 'pending' || request.status == 'acknowledged')
        .toList()
      ..sort((a, b) => (b.expiresAt ?? '').compareTo(a.expiresAt ?? ''));

    if (pending.isEmpty || _selectedTripId == null) {
      setState(() => _statusMessage =
          'You need a recent pickup request before boarding confirmation.');
      return;
    }

    PickupRequestModel? request;
    for (final candidate in pending) {
      if (candidate.tripSessionId == _selectedTripId) {
        request = candidate;
        break;
      }
    }
    request ??= pending.first;

    final session = context.read<SessionController>();
    final passengerService = PassengerService(session.apiClient);
    setState(() => _loading = true);

    try {
      await passengerService.validateBoarding(
        tripSessionId: _selectedTripId!,
        pickupRequestId: request.id,
      );
      setState(() => _statusMessage =
          'Boarding validated. Digital para alerts are now available.');
      await _load();
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendPara() async {
    final ride = _activeRide;
    if (ride == null || ride.status != 'onboard' || _selectedTripId == null) {
      setState(() => _statusMessage =
          'Digital para alert is only available for verified onboard riders.');
      return;
    }

    final payload = await _showStopAlertDialog();
    if (payload == null) return;
    if (!mounted) return;

    final session = context.read<SessionController>();
    final alerts = StopAlertService(session.apiClient);
    setState(() => _loading = true);

    try {
      await alerts.sendStopAlert(
        tripSessionId: _selectedTripId!,
        stopRef: payload.stopRef,
        note: payload.note,
      );
      setState(() => _statusMessage = 'Stop alert sent successfully.');
      await _load();
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancelRequest(String requestId) async {
    final session = context.read<SessionController>();
    final passengerService = PassengerService(session.apiClient);
    setState(() => _loading = true);

    try {
      await passengerService.cancelPickupRequest(requestId);
      setState(() => _statusMessage = 'Pickup request cancelled.');
      await _load();
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    final session = context.read<SessionController>();
    final notificationService = NotificationService(session.apiClient);
    try {
      await notificationService.markAllRead();
      await _load();
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    }
  }

  Future<_PassengerInput?> _showPickupDialog() async {
    final stopCtrl = TextEditingController(text: 'Nearest loading point');
    final noteCtrl = TextEditingController();
    final result = await showDialog<_PassengerInput>(
      context: context,
      builder: (context) {
        void submit() {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(context).pop(
            _PassengerInput(
              stopRef: stopCtrl.text.trim().isEmpty
                  ? 'Nearest loading point'
                  : stopCtrl.text.trim(),
              note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
            ),
          );
        }

        return AlertDialog(
          scrollable: true,
          title: const Text('Send pickup request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: stopCtrl,
                textInputAction: TextInputAction.next,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Pickup point or stop reference',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                textInputAction: TextInputAction.done,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => submit(),
                decoration: const InputDecoration(
                  labelText: 'Optional note',
                ),
                minLines: 2,
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submit,
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
    stopCtrl.dispose();
    noteCtrl.dispose();
    return result;
  }

  Future<_PassengerInput?> _showStopAlertDialog() async {
    final stopCtrl =
        TextEditingController(text: 'Next preferred drop-off point');
    final noteCtrl = TextEditingController();
    final result = await showDialog<_PassengerInput>(
      context: context,
      builder: (context) {
        void submit() {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(context).pop(
            _PassengerInput(
              stopRef: stopCtrl.text.trim().isEmpty
                  ? 'Next preferred drop-off point'
                  : stopCtrl.text.trim(),
              note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
            ),
          );
        }

        return AlertDialog(
          scrollable: true,
          title: const Text('Send digital para alert'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: stopCtrl,
                textInputAction: TextInputAction.next,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Drop-off reference',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                textInputAction: TextInputAction.done,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => submit(),
                decoration: const InputDecoration(
                  labelText: 'Optional note for driver',
                ),
                minLines: 2,
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submit,
              child: const Text('Alert driver'),
            ),
          ],
        );
      },
    );
    stopCtrl.dispose();
    noteCtrl.dispose();
    return result;
  }

  RouteSummaryModel? _routeById(String id) {
    for (final route in _routes) {
      if (route.id == id) return route;
    }
    return null;
  }

  String _tripRouteLabel(TripSession trip) {
    if (trip.routeName != null && trip.routeName!.isNotEmpty) {
      return trip.routeLabel;
    }
    final route = _routeById(trip.routeId);
    return route?.label ?? ParagoFormat.shortId(trip.routeId);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final unreadCount =
        _notifications.where((notification) => !notification.isRead).length;
    final pendingCount = _requests
        .where((request) =>
            request.status == 'pending' || request.status == 'acknowledged')
        .length;
    final onboardCount =
        _rides.where((ride) => ride.status == 'onboard').length;
    final selectedTrip = _selectedTrip;
    final activeRide = _activeRide;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Passenger Console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => session.logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _RoleHero(
              title: 'Ready for your next jeepney ride',
              subtitle:
                  'Send pickup requests quickly, confirm boarding without QR, and trigger digital para alerts only when verified onboard.',
              accent: Theme.of(context).colorScheme.secondary,
              badge: session.user?.fullName ?? 'Passenger',
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              _InfoBanner(message: _statusMessage!),
            ],
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 640;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: compact ? 1 : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: compact ? 1.7 : 1.05,
                  children: [
                    MetricCard(
                      label: 'Active trips',
                      value: _trips.length.toString(),
                      icon: Icons.route_outlined,
                      accent: const Color(0xFF0F6A5F),
                      caption:
                          'Trips currently accepting or serving passengers',
                    ),
                    MetricCard(
                      label: 'Pending requests',
                      value: pendingCount.toString(),
                      icon: Icons.near_me_outlined,
                      accent: const Color(0xFFE29B2D),
                      caption:
                          'Requests waiting for acknowledgement or boarding',
                    ),
                    MetricCard(
                      label: 'Onboard rides',
                      value: onboardCount.toString(),
                      icon: Icons.directions_bus_filled_outlined,
                      accent: const Color(0xFF2157A5),
                      caption:
                          'Verified ride sessions with para support enabled',
                    ),
                    MetricCard(
                      label: 'Unread notices',
                      value: unreadCount.toString(),
                      icon: Icons.notifications_active_outlined,
                      accent: const Color(0xFF7B4F9D),
                      caption:
                          'Pickup, boarding, and trip updates from the backend',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Commute actions',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                      'The core passenger flow stays short: request pickup, confirm boarding, then send para when onboard.',
                    ),
                    const SizedBox(height: 18),
                    _PassengerActionButton(
                      icon: Icons.location_searching_outlined,
                      title: 'Send pickup request',
                      subtitle:
                          'Notify a currently active trip where you want to board',
                      onPressed: _loading ? null : _sendPickup,
                    ),
                    const SizedBox(height: 12),
                    _PassengerActionButton(
                      icon: Icons.fact_check_outlined,
                      title: 'I boarded',
                      subtitle:
                          'Validate recent pickup request and activate the ride session',
                      onPressed: _loading ? null : _board,
                    ),
                    const SizedBox(height: 12),
                    _PassengerActionButton(
                      icon: Icons.notifications_active_outlined,
                      title: 'Send digital para alert',
                      subtitle:
                          'Available only for verified onboard passengers',
                      onPressed: _loading || activeRide?.status != 'onboard'
                          ? null
                          : _sendPara,
                      highlight: const Color(0xFFE29B2D),
                    ),
                    if (_loading) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trip focus',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    if (_trips.isEmpty)
                      const Text(
                          'No active jeepney trips are available right now.')
                    else ...[
                      DropdownButtonFormField<String>(
                        initialValue: _selectedTripId,
                        items: _trips
                            .map(
                              (trip) => DropdownMenuItem<String>(
                                value: trip.id,
                                child: Text(_tripRouteLabel(trip)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          final trip =
                              _trips.firstWhere((entry) => entry.id == value);
                          setState(() {
                            _selectedTripId = value;
                            _selectedRouteId = trip.routeId;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      if (selectedTrip != null) ...[
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            StatusBadge(status: selectedTrip.status),
                            StatusBadge(
                              status: selectedTrip.acceptRequests == false
                                  ? 'paused'
                                  : 'active',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _DetailRow(
                          label: 'Route',
                          value: _tripRouteLabel(selectedTrip),
                        ),
                        _DetailRow(
                          label: 'Jeepney',
                          value: selectedTrip.jeepneyLabel.isEmpty
                              ? ParagoFormat.shortId(selectedTrip.jeepneyId)
                              : selectedTrip.jeepneyLabel,
                        ),
                        _DetailRow(
                          label: 'Started',
                          value: ParagoFormat.dateTime(selectedTrip.startedAt),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ride session',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    if (activeRide == null)
                      const Text(
                        'No verified ride session yet. Send a pickup request, then confirm boarding after entering the jeepney.',
                      )
                    else ...[
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          StatusBadge(status: activeRide.status),
                          if (activeRide.canSendStopAlert == true)
                            const StatusBadge(status: 'para enabled'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _DetailRow(
                        label: 'Ride session',
                        value: ParagoFormat.shortId(activeRide.id),
                      ),
                      _DetailRow(
                        label: 'Boarded',
                        value: ParagoFormat.dateTime(activeRide.boardedAt),
                      ),
                      _DetailRow(
                        label: 'Pickup request',
                        value: ParagoFormat.shortId(activeRide.pickupRequestId),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      title: 'My pickup requests',
                      trailing: Text('${_requests.length} total'),
                    ),
                    const SizedBox(height: 8),
                    if (_requests.isEmpty)
                      const Text('No pickup requests yet for this account.')
                    else
                      for (final request in _requests.take(6)) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              request.stopRef ?? 'Unspecified pickup point'),
                          subtitle: Text(
                            '${ParagoFormat.statusLabel(request.status)} · ${ParagoFormat.relative(request.createdAt)}',
                          ),
                          trailing: request.status == 'pending'
                              ? TextButton(
                                  onPressed: () => _cancelRequest(request.id),
                                  child: const Text('Cancel'),
                                )
                              : StatusBadge(status: request.status),
                        ),
                        const Divider(),
                      ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      title: 'Notifications',
                      trailing: TextButton(
                        onPressed: unreadCount == 0 ? null : _markAllRead,
                        child: const Text('Mark all read'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_notifications.isEmpty)
                      const Text('No notifications yet.')
                    else
                      for (final notification in _notifications.take(5)) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            notification.isRead
                                ? Icons.mark_email_read_outlined
                                : Icons.notifications_active,
                            color: notification.isRead
                                ? Theme.of(context).colorScheme.outline
                                : Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(notification.title),
                          subtitle: Text(
                            '${notification.body}\n${ParagoFormat.relative(notification.createdAt)}',
                          ),
                          isThreeLine: true,
                        ),
                        const Divider(),
                      ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Available routes',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    if (_routes.isEmpty)
                      const Text('Route list unavailable.')
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _routes
                            .map(
                              (route) => Chip(
                                label: Text('${route.code} · ${route.name}'),
                                avatar: CircleAvatar(
                                  backgroundColor: Colors.transparent,
                                  child: Text('${route.stopsCount}'),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassengerInput {
  const _PassengerInput({
    required this.stopRef,
    this.note,
  });

  final String stopRef;
  final String? note;
}

class _RoleHero extends StatelessWidget {
  const _RoleHero({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.badge,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            accent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PassengerActionButton extends StatelessWidget {
  const _PassengerActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.highlight,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
