import 'glass_surface.dart';
import 'package:flutter/material.dart';
import '../services/passenger_service.dart';

class GroupBookingDialog extends StatefulWidget {
  const GroupBookingDialog(
      {super.key,
      required this.service,
      required this.basePayload,
      required this.destinations,
      required this.maxSeats});
  final PassengerService service;
  final Map<String, dynamic> basePayload;
  final List<Map<String, dynamic>> destinations;
  final int maxSeats;
  @override
  State<GroupBookingDialog> createState() => _GroupBookingDialogState();
}

class _GroupBookingDialogState extends State<GroupBookingDialog> {
  final List<int?> _destinations = [null];
  Map<String, dynamic>? _quote;
  bool _busy = false;
  String? _error;
  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      ...widget.basePayload,
      'flowVersion': 2,
      'quoteToken': _quote!['quoteToken'],
      'members': _quote!['members'],
      'partySize': _destinations.length,
    };
    try {
      await widget.service.createQuotedBooking(body);
      if (mounted) Navigator.pop(context, {...body, '_bookingCreated': true});
    } catch (e) {
      // Keep every selected destination on errors. A changed quote is reviewed
      // in this same dialog; no booking is retried without another user tap.
      if (mounted) {
        setState(() {
          _quote = null;
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    if (_destinations.any((d) => d == null)) {
      setState(() => _error = 'Choose a drop-off for every passenger.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final quote = await widget.service.quoteBooking({
        ...widget.basePayload,
        'members': _destinations.map((d) => widget.destinations[d!]).toList()
      });
      if (mounted) setState(() => _quote = quote);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = (_quote?['members'] as List?) ?? const [];
    return GlassAlertDialog(
      scrollable: true,
      title: const Text('Booking'),
      content: SizedBox(
          width: 360,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Pickup: ${widget.basePayload['stopRef'] ?? 'Selected pickup'}'),
                const SizedBox(height: 12),
                for (var i = 0; i < _destinations.length; i++) ...[
                  DropdownButtonFormField<int>(
                      key: ValueKey('destination-$i-${_destinations[i]}'),
                      initialValue: _destinations[i],
                      isExpanded: true,
                      isDense: false,
                      itemHeight: null,
                      decoration: InputDecoration(
                          labelText: i == 0 ? 'You' : 'Passenger ${i + 1}',
                          hintText: 'Drop-off'),
                      items: List.generate(
                          widget.destinations.length,
                          (d) => DropdownMenuItem(
                              value: d,
                              child: Text(
                                  widget.destinations[d]['destinationStopRef']
                                      .toString(),
                                  softWrap: true))),
                      onChanged: _busy
                          ? null
                          : (d) => setState(() {
                                _destinations[i] = d;
                                _quote = null;
                                _error = null;
                              })),
                  if (i < members.length)
                    Text(
                        'Fare: ₱${(members[i]['fareSnapshot']['amount'] as num).toStringAsFixed(2)}'),
                  const SizedBox(height: 12),
                ],
                Wrap(spacing: 12, runSpacing: 12, children: [
                  TextButton.icon(
                      onPressed:
                          !_busy && _destinations.length < widget.maxSeats
                              ? () => setState(() {
                                    _destinations.add(null);
                                    _quote = null;
                                  })
                              : null,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add')),
                  if (_destinations.length > 1)
                    TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _destinations.removeLast();
                                  _quote = null;
                                }),
                        child: const Text('Remove')),
                ]),
                Text('Seats: ${widget.maxSeats}'),
                if (_quote != null)
                  Text(
                      'Total: ₱${(_quote!['regularTotal'] as num).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                if (_error != null)
                  Text(_error!,
                      style: const TextStyle(
                          color: Color(0xFFFFB4AB), height: 1.5)),
              ])),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _busy
                ? null
                : _quote == null
                    ? _review
                    : _submit,
            child: Text(_busy
                ? 'Checking…'
                : _quote == null
                    ? 'Review'
                    : 'Book'))
      ],
    );
  }
}
