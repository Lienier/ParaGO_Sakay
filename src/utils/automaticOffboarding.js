const evaluateAutoOffboardingSeparation = ({
  distanceMeters,
  separationStartedAt,
  outsideCount = 0,
  now = new Date(),
  separationMeters = 120,
  consecutiveOutsideChecks = 3,
  sustainedSeparationSeconds = 60,
}) => {
  const distance = Number(distanceMeters);
  const currentTime = now instanceof Date ? now : new Date(now);
  const outside =
    Number.isFinite(distance) &&
    Number.isFinite(Number(separationMeters)) &&
    distance >= Number(separationMeters);

  if (!outside || Number.isNaN(currentTime.getTime())) {
    return {
      outside: false,
      shouldOffboard: false,
      separationStartedAt: null,
      outsideCount: 0,
      separationMilliseconds: 0,
    };
  }

  const existingStart = separationStartedAt
    ? new Date(separationStartedAt)
    : currentTime;
  const startedAt = Number.isNaN(existingStart.getTime())
    ? currentTime
    : existingStart;
  const nextOutsideCount = Math.max(0, Number(outsideCount) || 0) + 1;
  const separationMilliseconds = Math.max(
    0,
    currentTime.getTime() - startedAt.getTime()
  );
  const requiredSeparationMilliseconds =
    Math.max(0, Number(sustainedSeparationSeconds) || 0) * 1000;

  return {
    outside: true,
    shouldOffboard:
      nextOutsideCount >= Number(consecutiveOutsideChecks || 0) ||
      separationMilliseconds >= requiredSeparationMilliseconds,
    separationStartedAt: startedAt,
    outsideCount: nextOutsideCount,
    separationMilliseconds,
  };
};

module.exports = { evaluateAutoOffboardingSeparation };
