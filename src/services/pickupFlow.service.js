const normalizePickupRequestStatus = (value) =>
  String(value || '')
    .trim()
    .toLowerCase();

const normalizePickupType = (value) =>
  String(value || '')
    .trim()
    .toLowerCase() === 'terminal'
  ? 'terminal'
  : 'roadside';

const isOpenPickupRequestStatus = (value) =>
  ['pending', 'acknowledged'].includes(normalizePickupRequestStatus(value));

const canDriverAcknowledgePickupRequest = (value) =>
  normalizePickupRequestStatus(value) === 'pending';

const canPassengerBoardPickupRequest = (value, options = {}) => {
  const status = normalizePickupRequestStatus(value);
  const pickupType = normalizePickupType(options.pickupType);
  if (pickupType === 'terminal') {
    return status === 'acknowledged';
  }
  return status === 'acknowledged';
};

const canPassengerCancelPickupRequest = (value) =>
  isOpenPickupRequestStatus(value);

module.exports = {
  normalizePickupRequestStatus,
  normalizePickupType,
  isOpenPickupRequestStatus,
  canDriverAcknowledgePickupRequest,
  canPassengerBoardPickupRequest,
  canPassengerCancelPickupRequest,
};
