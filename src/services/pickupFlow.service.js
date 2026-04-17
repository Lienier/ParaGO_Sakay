const normalizePickupRequestStatus = (value) =>
  String(value || '')
    .trim()
    .toLowerCase();

const isOpenPickupRequestStatus = (value) =>
  ['pending', 'acknowledged'].includes(normalizePickupRequestStatus(value));

const canDriverAcknowledgePickupRequest = (value) =>
  normalizePickupRequestStatus(value) === 'pending';

const canPassengerBoardPickupRequest = (value) =>
  normalizePickupRequestStatus(value) === 'acknowledged';

const canPassengerCancelPickupRequest = (value) =>
  isOpenPickupRequestStatus(value);

module.exports = {
  normalizePickupRequestStatus,
  isOpenPickupRequestStatus,
  canDriverAcknowledgePickupRequest,
  canPassengerBoardPickupRequest,
  canPassengerCancelPickupRequest,
};
