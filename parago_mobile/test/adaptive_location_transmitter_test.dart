import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/models/operations/driver_location_update.dart';
import 'package:parago_mobile/services/adaptive_location_transmitter.dart';

void main() {
  const firstStream = '11111111-1111-4111-8111-111111111111';

  test('first sample is sent immediately with ordered metadata', () async {
    final sent = <DriverLocationUpdate>[];
    final transmitter = AdaptiveLocationTransmitter(
      streamIdFactory: () => firstStream,
      sender: (update) async {
        sent.add(update);
        return acknowledgementFor(update);
      },
    )..start();

    transmitter.addSample(sample(latitude: 14.5, longitude: 120.9));
    await waitFor(() => sent.length == 1);

    expect(sent.single.streamId, firstStream);
    expect(sent.single.sequence, 1);
    expect(sent.single.accuracyMeters, 5);
    transmitter.dispose();
  });

  test('network backlog keeps only the newest unsent position', () async {
    final sent = <DriverLocationUpdate>[];
    final firstResponse = Completer<DriverLocationAcknowledgement>();
    final transmitter = AdaptiveLocationTransmitter(
      streamIdFactory: () => firstStream,
      sender: (update) {
        sent.add(update);
        if (sent.length == 1) return firstResponse.future;
        return Future.value(acknowledgementFor(update));
      },
    )..start();

    transmitter.addSample(sample(latitude: 14.5, longitude: 120.9));
    await waitFor(() => sent.length == 1);
    transmitter.addSample(sample(latitude: 14.501, longitude: 120.901));
    transmitter.addSample(sample(latitude: 14.502, longitude: 120.902));

    firstResponse.complete(acknowledgementFor(sent.first));
    await waitFor(() => sent.length == 2);

    expect(sent[1].latitude, 14.502);
    expect(sent[1].longitude, 120.902);
    expect(sent[1].sequence, 2);
    transmitter.dispose();
  });

  test('moving reports sooner than stationary without resending old samples',
      () async {
    final moving = <DriverLocationUpdate>[];
    final stationary = <DriverLocationUpdate>[];
    final movingTransmitter = AdaptiveLocationTransmitter(
      movingInterval: const Duration(milliseconds: 30),
      stationaryInterval: const Duration(milliseconds: 90),
      meaningfulMovementMeters: 1000,
      streamIdFactory: () => firstStream,
      sender: (update) async {
        moving.add(update);
        return acknowledgementFor(update);
      },
    )..start();
    final stationaryTransmitter = AdaptiveLocationTransmitter(
      movingInterval: const Duration(milliseconds: 30),
      stationaryInterval: const Duration(milliseconds: 90),
      meaningfulMovementMeters: 1000,
      streamIdFactory: () => '22222222-2222-4222-8222-222222222222',
      sender: (update) async {
        stationary.add(update);
        return acknowledgementFor(update);
      },
    )..start();

    movingTransmitter.addSample(sample(speed: 5));
    stationaryTransmitter.addSample(sample(speed: 0));
    await waitFor(() => moving.length == 1 && stationary.length == 1);
    movingTransmitter.addSample(sample(speed: 5));
    stationaryTransmitter.addSample(sample(speed: 0));
    await Future<void>.delayed(const Duration(milliseconds: 55));

    expect(moving, hasLength(2));
    expect(stationary, hasLength(1));
    await waitFor(() => stationary.length == 2);
    movingTransmitter.dispose();
    stationaryTransmitter.dispose();
  });

  test('tracking restart creates a new stream and resets sequence', () async {
    final streams = <String>[
      firstStream,
      '33333333-3333-4333-8333-333333333333',
    ];
    final sent = <DriverLocationUpdate>[];
    final transmitter = AdaptiveLocationTransmitter(
      streamIdFactory: () => streams.removeAt(0),
      sender: (update) async {
        sent.add(update);
        return acknowledgementFor(update);
      },
    )..start();

    transmitter.addSample(sample());
    await waitFor(() => sent.length == 1);
    await transmitter.stop(sendFinal: false);
    transmitter.start();
    transmitter.addSample(sample());
    await waitFor(() => sent.length == 2);

    expect(sent[0].sequence, 1);
    expect(sent[1].sequence, 1);
    expect(sent[0].streamId, isNot(sent[1].streamId));
    transmitter.dispose();
  });

  test('failed attempt is not retried until a newer sample arrives', () async {
    final sent = <DriverLocationUpdate>[];
    final transmitter = AdaptiveLocationTransmitter(
      movingInterval: const Duration(milliseconds: 20),
      stationaryInterval: const Duration(milliseconds: 20),
      meaningfulMovementMeters: 1000,
      streamIdFactory: () => firstStream,
      sender: (update) async {
        sent.add(update);
        if (sent.length == 1) throw StateError('stale update');
        return acknowledgementFor(update);
      },
    )..start();

    transmitter.addSample(sample());
    await waitFor(() => transmitter.updatesFailed == 1);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(sent, hasLength(1));

    transmitter.addSample(sample());
    await waitFor(() => sent.length == 2);
    expect(sent.last.sequence, 2);
    transmitter.dispose();
  });

  test('reconnect flush sends the latest coalesced sample immediately',
      () async {
    final sent = <DriverLocationUpdate>[];
    final transmitter = AdaptiveLocationTransmitter(
      movingInterval: const Duration(seconds: 5),
      stationaryInterval: const Duration(seconds: 5),
      meaningfulMovementMeters: 1000,
      streamIdFactory: () => firstStream,
      sender: (update) async {
        sent.add(update);
        return acknowledgementFor(update);
      },
    )..start();

    transmitter.addSample(sample());
    await waitFor(() => sent.length == 1);
    transmitter.addSample(sample(latitude: 14.50001));
    await transmitter.sendLatestNow();

    expect(sent, hasLength(2));
    expect(sent.last.latitude, 14.50001);
    expect(sent.last.sequence, 2);
    transmitter.dispose();
  });

  test('meaningful heading change sends immediately while moving', () async {
    final sent = <DriverLocationUpdate>[];
    final transmitter = AdaptiveLocationTransmitter(
      movingInterval: const Duration(seconds: 5),
      meaningfulMovementMeters: 1000,
      meaningfulHeadingDegrees: 20,
      streamIdFactory: () => firstStream,
      sender: (update) async {
        sent.add(update);
        return acknowledgementFor(update);
      },
    )..start();

    transmitter.addSample(sample(heading: 10));
    await waitFor(() => sent.length == 1);
    transmitter.addSample(sample(heading: 45));
    await waitFor(() => sent.length == 2);

    expect(sent.last.headingDegrees, 45);
    transmitter.dispose();
  });
}

DriverLocationSample sample({
  double latitude = 14.5,
  double longitude = 120.9,
  double speed = 4,
  double heading = 90,
}) {
  return DriverLocationSample(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: 5,
    speedMetersPerSecond: speed,
    headingDegrees: heading,
    capturedAt: DateTime.now().toUtc(),
  );
}

DriverLocationAcknowledgement acknowledgementFor(
  DriverLocationUpdate update,
) {
  return DriverLocationAcknowledgement(
    accepted: true,
    streamId: update.streamId,
    sequence: update.sequence,
    serverReceivedAt: DateTime.now().toUtc(),
  );
}

Future<void> waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}
