const evaluateAutoBoardingProximity = ({
  distanceMeters,
  proximityStartedAt,
  now = new Date(),
  proximityMeters = 25,
  dwellSeconds = 10,
}) => {
  const distance = Number(distanceMeters);
  const currentTime = now instanceof Date ? now : new Date(now);
  const near =
    Number.isFinite(distance) &&
    Number.isFinite(Number(proximityMeters)) &&
    distance <= Number(proximityMeters);

  if (!near || Number.isNaN(currentTime.getTime())) {
    return {
      near: false,
      shouldBoard: false,
      proximityStartedAt: null,
      dwellMilliseconds: 0,
    };
  }

  const existingStart = proximityStartedAt
    ? new Date(proximityStartedAt)
    : currentTime;
  const startedAt = Number.isNaN(existingStart.getTime())
    ? currentTime
    : existingStart;
  const dwellMilliseconds = Math.max(
    0,
    currentTime.getTime() - startedAt.getTime()
  );
  const requiredDwellMilliseconds = Math.max(0, Number(dwellSeconds) || 0) * 1000;

  return {
    near: true,
    shouldBoard: dwellMilliseconds >= requiredDwellMilliseconds,
    proximityStartedAt: startedAt,
    dwellMilliseconds,
  };
};

module.exports = { evaluateAutoBoardingProximity };
