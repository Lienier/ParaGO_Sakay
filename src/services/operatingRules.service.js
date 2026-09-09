const Holiday = require('../models/codingHoliday');
const ApiError = require('../utils/apiError');
const LOADING_MS = 10 * 60 * 1000;
function manilaDate(now = new Date()) {
  return new Date(now.getTime() + 8 * 3600000).toISOString().slice(0, 10);
}
function codingRestricted(plate, date, holiday = false) {
  const weekday = new Date(`${date}T00:00:00Z`).getUTCDay();
  if (holiday || weekday === 0 || weekday === 6) return false;
  const digit = String(plate || '').match(/(\d)\D*$/)?.[1];
  if (digit == null) throw new ApiError(409, 'Jeep plate needs a numeric ending before operation');
  return [weekday * 2 - 1, weekday * 2 % 10].includes(Number(digit));
}
async function assertVehicleAllowed(vehicle, session, now = new Date()) {
  if (!vehicle) throw new ApiError(409, 'Jeep is unavailable');
  const date = manilaDate(now);
  const holiday = await Holiday.exists({ date }).session(session || null);
  if (codingRestricted(vehicle.plateNumber, date, Boolean(holiday))) {
    throw new ApiError(409, `Jeep ${vehicle.plateNumber} cannot operate today (${date}): number coding. Your account remains active.`);
  }
}
function loadingTiming(trip, now = new Date()) {
  if (trip.operatingMode !== 'terminal_queue' || trip.terminalQueueStatus !== 'loading') return {};
  const start = trip.terminalLoadingStartedAt;
  const deadline = start ? new Date(new Date(start).getTime() + LOADING_MS) : null;
  const remainingSeconds = deadline ? Math.max(0, Math.ceil((deadline - now) / 1000)) : 0;
  return { serverTime: now, loadingDeadline: deadline, remainingSeconds,
    departureRequired: remainingSeconds === 0, loadingWarning: remainingSeconds <= 120,
    loadingTimerUnavailable: !deadline };
}
module.exports = { manilaDate, codingRestricted, assertVehicleAllowed, loadingTiming, LOADING_MS };
