import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const manifest = JSON.parse(open('../../.secure-backups/phase10-load-manifest.json'));
const baseUrl = String(__ENV.BASE_URL || '').replace(/\/$/, '');
const driverVus = Number(__ENV.DRIVER_VUS || 5);
const passengerVus = Number(__ENV.PASSENGER_VUS || 20);
const duration = __ENV.DURATION || '5m';
const liveGoogle = __ENV.ALLOW_LIVE_GOOGLE === 'true';

if (!baseUrl || (!baseUrl.includes('staging') && !baseUrl.includes('127.0.0.1'))) {
  throw new Error('BASE_URL must identify the isolated staging service');
}
if (liveGoogle && __ENV.GOOGLE_BUDGET_APPROVED !== 'true') {
  throw new Error('Live Google validation requires GOOGLE_BUDGET_APPROVED=true');
}
if (driverVus > manifest.drivers.length || passengerVus > manifest.passengers.length) {
  throw new Error('Requested VUs exceed the synthetic staging manifest');
}

const locationLatency = new Trend('parago_location_latency', true);
const ordinaryLatency = new Trend('parago_ordinary_latency', true);
const etaLatency = new Trend('parago_eta_latency', true);
const requestErrors = new Rate('parago_request_errors');
const staleRejections = new Counter('parago_stale_rejections');

export const options = {
  scenarios: {
    drivers: {
      executor: 'constant-vus',
      exec: 'driverTraffic',
      vus: driverVus,
      duration,
      gracefulStop: '10s',
    },
    passengers: {
      executor: 'constant-vus',
      exec: 'passengerTraffic',
      vus: passengerVus,
      duration,
      gracefulStop: '10s',
    },
  },
  thresholds: {
    parago_location_latency: ['p(95)<250'],
    parago_ordinary_latency: ['p(95)<500'],
    parago_request_errors: ['rate<0.01'],
    http_req_failed: ['rate<0.01'],
  },
};

const headersFor = (token) => ({
  Authorization: `Bearer ${token}`,
  'Content-Type': 'application/json',
});

const driverState = new Map();

export function driverTraffic() {
  const index = (__VU - 1) % driverVus;
  const account = manifest.drivers[index];
  const state = driverState.get(__VU) || {
    sequence: 0,
    streamId: `phase10-${index}-${Date.now()}-${Math.random().toString(16).slice(2)}`,
  };
  state.sequence += 1;
  driverState.set(__VU, state);
  const routePoint = manifest.routeCoordinates[
    state.sequence % manifest.routeCoordinates.length
  ];
  const response = http.patch(
    `${baseUrl}/api/v1/drivers/me/location`,
    JSON.stringify({
      latitude: routePoint[1] + index * 0.000001,
      longitude: routePoint[0] + index * 0.000001,
      accuracyMeters: 8,
      speedMetersPerSecond: 8,
      headingDegrees: 45,
      streamId: state.streamId,
      sequence: state.sequence,
      capturedAt: new Date().toISOString(),
    }),
    { headers: headersFor(account.token), tags: { domain: 'driver_location' } }
  );
  locationLatency.add(response.timings.duration);
  const accepted = check(response, {
    'driver location accepted': (value) =>
      value.status === 200 && value.json('data.accepted') === true,
  });
  requestErrors.add(!accepted);
  if (response.status === 409) staleRejections.add(1);
  sleep(2);
}

export function passengerTraffic() {
  const index = (__VU - 1) % passengerVus;
  const account = manifest.passengers[index];
  const headers = headersFor(account.token);
  const responses = http.batch([
    ['GET', `${baseUrl}/api/v1/trips/active`, null, { headers, tags: { domain: 'trips' } }],
    ['GET', `${baseUrl}/api/v1/routes`, null, { headers, tags: { domain: 'routes' } }],
    ['GET', `${baseUrl}/api/v1/announcements/active`, null, { headers, tags: { domain: 'announcements' } }],
  ]);
  for (const response of responses) {
    ordinaryLatency.add(response.timings.duration);
    const successful = check(response, {
      'ordinary request succeeds': (value) => value.status === 200,
    });
    requestErrors.add(!successful);
  }

  if (liveGoogle && index === 0) {
    const trip = manifest.drivers[0];
    const destination =
      manifest.routeCoordinates[manifest.routeCoordinates.length - 1];
    const eta = http.post(
      `${baseUrl}/api/v1/trips/${trip.tripId}/passenger-eta`,
      JSON.stringify({
        destination: { latitude: destination[1], longitude: destination[0] },
      }),
      { headers, tags: { domain: 'live_google_eta' } }
    );
    etaLatency.add(eta.timings.duration);
    const successful = check(eta, {
      'live ETA succeeds': (value) => value.status === 200,
    });
    requestErrors.add(!successful);
  }
  sleep(30);
}

export function handleSummary(data) {
  const profile = `${driverVus}d-${passengerVus}p`;
  return {
    [`artifacts/phase10/${profile}-rest-summary.json`]: JSON.stringify(data, null, 2),
    stdout: `Phase 10 REST profile ${profile} complete.\n`,
  };
}
