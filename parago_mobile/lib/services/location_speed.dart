/// Position requires a number. A negative sentinel preserves an unavailable
/// sensor value until the transmitter encodes it as null, rather than stopped.
double sensorSpeed(double? value) =>
    value != null && value.isFinite && value >= 0 ? value : -1;
