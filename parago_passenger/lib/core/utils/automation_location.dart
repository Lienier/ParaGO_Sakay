bool isUsableAutomationLocation({
  required DateTime capturedAt,
  required DateTime now,
  required double accuracyMeters,
}) {
  final age = now.difference(capturedAt);
  return !age.isNegative &&
      age <= const Duration(seconds: 15) &&
      accuracyMeters.isFinite &&
      accuracyMeters >= 0 &&
      accuracyMeters <= 35;
}
