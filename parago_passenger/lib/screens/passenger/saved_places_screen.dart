import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/network/api_client.dart';

class PlaceSource {
  const PlaceSource(this.name, this.point);
  final String name;
  final LatLng point;
}

class SavedPlaceSelection {
  const SavedPlaceSelection(this.point, this.forPickup);
  final LatLng point;
  final bool forPickup;
}

class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen(
      {super.key,
      required this.client,
      required this.sources,
      required this.accountChanges,
      required this.isCurrentAccount});
  final ApiClient client;
  final List<PlaceSource> sources;
  final Listenable accountChanges;
  final bool Function() isCurrentAccount;
  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  List<Map<String, dynamic>> _places = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.accountChanges.addListener(_accountChanged);
    _request('GET');
  }

  void _accountChanged() {
    if (!widget.isCurrentAccount() && mounted) {
      setState(() {
        _places = [];
        _busy = true;
        _error = 'Your session changed. Close this page and sign in again.';
      });
    }
  }

  @override
  void dispose() {
    widget.accountChanges.removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> _request(String method,
      {String suffix = '', Map<String, dynamic>? body}) async {
    if (!widget.isCurrentAccount()) {
      _accountChanged();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.client.request(
          method: method,
          path: '/passengers/me/saved-places$suffix',
          body: body,
          useCache: false);
      final places = (response['data'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      if (mounted && widget.isCurrentAccount()) {
        setState(() => _places = places);
      }
    } catch (e) {
      if (mounted && widget.isCurrentAccount()) {
        setState(() => _error = 'Could not complete the request: $e');
      }
    } finally {
      if (mounted && widget.isCurrentAccount()) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    var name = '';
    final form = GlobalKey<FormState>();
    var source = widget.sources.first;
    final body = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: const Text('Save a place'),
                  content: SingleChildScrollView(
                      child: Form(
                          key: form,
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            TextFormField(
                                onChanged: (value) => name = value,
                                maxLength: 60,
                                autofocus: true,
                                decoration: const InputDecoration(
                                    labelText: 'Name',
                                    hintText: 'Home, Work, School'),
                                validator: (value) =>
                                    (value ?? '').trim().isEmpty
                                        ? 'Enter a place name'
                                        : null),
                            DropdownButtonFormField<PlaceSource>(
                                initialValue: source,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Location to save'),
                                items: widget.sources
                                    .map((s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(s.name,
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    update(() => source = value);
                                  }
                                }),
                            const SizedBox(height: 12),
                            const Text(
                                'To save a different location, go back and pin it on the map first.'),
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () {
                          if (form.currentState!.validate()) {
                            Navigator.pop(context, <String, dynamic>{
                              'name': name.trim(),
                              'lat': source.point.latitude,
                              'lng': source.point.longitude
                            });
                          }
                        },
                        child: const Text('Save'))
                  ],
                )));
    if (mounted && body != null) await _request('POST', body: body);
  }

  Future<void> _remove(Map<String, dynamic> place) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Remove saved place?'),
                content: Text(
                    'Remove ${place['name']}? Existing bookings will stay unchanged.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Remove'))
                ]));
    if (mounted && confirmed == true) {
      await _request('DELETE', suffix: '/${place['_id']}');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Saved Places'), actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : () => _request('GET'),
              icon: const Icon(Icons.refresh))
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              'Save locations for your next booking. Selecting a place still checks the selected route and your pickup location.'),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (!_busy && _places.isEmpty && _error == null)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No saved places yet.')),
          for (final place in _places)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(place['name'] as String,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                              '${(place['lat'] as num).toStringAsFixed(5)}, ${(place['lng'] as num).toStringAsFixed(5)}'),
                          Wrap(spacing: 8, children: [
                            for (final pickup in [true, false])
                              TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => Navigator.pop(
                                          context,
                                          SavedPlaceSelection(
                                              LatLng(
                                                  (place['lat'] as num)
                                                      .toDouble(),
                                                  (place['lng'] as num)
                                                      .toDouble()),
                                              pickup)),
                                  child: Text(pickup
                                      ? 'Use as pickup'
                                      : 'Use as unload')),
                            TextButton(
                                onPressed: _busy ? null : () => _remove(place),
                                child: const Text('Remove')),
                          ]),
                        ]))),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: _busy || widget.sources.isEmpty || _places.length >= 20
                  ? null
                  : _add,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add a place')),
          if (widget.sources.isEmpty)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                    'Pin a pickup or unload location on the map, then return here to save it.')),
          const SizedBox(height: 8),
          Text('${_places.length}/20 places saved'),
        ]),
      );
}
