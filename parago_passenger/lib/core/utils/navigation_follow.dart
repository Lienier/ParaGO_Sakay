/// Camera mode is independent of refresh, reconnect and application lifecycle.
class NavigationFollow {
  bool following = true;
  int generation = 0;
  String? _target;
  double? _heading;

  double get heading => _heading ?? 0;

  void freeView() {
    following = false;
    generation++;
  }

  void recenter() {
    following = true;
    generation++;
  }

  static bool isFresh(DateTime? sample, DateTime now) {
    if (sample == null) return false;
    final age = now.difference(sample);
    return !age.isNegative && age <= const Duration(seconds: 30);
  }

  void updateHeading({
    required String target,
    required DateTime? sample,
    required DateTime now,
    double? bearing,
    double? speed,
  }) {
    if (_target != target) {
      _target = target;
      _heading = null;
    }
    if (!isFresh(sample, now) ||
        bearing == null ||
        !bearing.isFinite ||
        bearing < 0 ||
        bearing >= 360 ||
        speed == null ||
        !speed.isFinite ||
        speed < 1) {
      return;
    }
    final previous = _heading;
    if (previous == null) {
      _heading = bearing;
      return;
    }
    final difference = (bearing - previous + 540) % 360 - 180;
    _heading = (previous + difference * 0.25 + 360) % 360;
  }
}
