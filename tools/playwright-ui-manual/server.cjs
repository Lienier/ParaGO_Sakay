// Synthetic fixtures and GPS for three real Flutter browser UIs. Loopback only.
const { createLab } = require('./fixture.cjs');
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
(async () => {
  const lab = await createLab();
  const express = require('express'); const controls = express(); controls.use(express.json());
  let streamId = crypto.randomUUID(), sequence = 0;
  const Ride = require('../../src/models/rideSession'), Pickup = require('../../src/models/pickupRequest');
  async function token(actor) {
    const user = lab.accounts[actor];
    const session = await require('../../src/models/authSession').findOne({ userId: user._id, revokedAt: null, expiresAt: { $gt: new Date() } }).sort({ createdAt: -1 });
    return session ? require('../../src/utils/jwt').signToken({ sub: String(user._id), sid: session._id }) : lab.syntheticToken(user);
  }
  controls.get('/state', async (_req,res) => res.json({ trips: await lab.models.Trip.find().lean(), bookings: await Pickup.find().lean(), rides: await Ride.find().lean(), events: await require('../../src/models/activityLog').find().lean() }));
  controls.get('/otp', (_req,res) => res.json({ code: lab.mailbox.at(-1)?.text.match(/\b\d{6}\b/)?.[0] }));
  controls.get('/fixture', (_req,res) => res.json({ ids: lab.ids, accounts: Object.fromEntries(Object.entries(lab.accounts).map(([k,v])=>[k,v.email])), password: lab.password }));
  controls.post('/gps', async (req,res) => {
    const actor = req.body.actor || 'driver';
    const data = actor === 'driver' ? { latitude: req.body.latitude, longitude: 121.05, accuracyMeters: req.body.accuracy ?? 5,
      speedMetersPerSecond: req.body.speed === undefined ? 0 : req.body.speed, streamId, sequence: ++sequence, capturedAt: new Date(Date.now()-(req.body.ageMs || 0)).toISOString() }
      : { lat: req.body.latitude, lng: 121.05, capturedAt: new Date().toISOString() };
    const response = await fetch(`${lab.apiOrigin}/api/v1/${actor === 'driver' ? 'drivers' : 'passengers'}/me/location`, { method: 'PATCH', headers: { Authorization: `Bearer ${await token(actor)}`, 'Content-Type': 'application/json', 'X-App-Build': '21' }, body: JSON.stringify(data) });
    res.status(response.status).json(await response.json());
  });
  controls.post('/reset', async (req,res) => {
    for (const Model of [Ride, Pickup, require('../../src/models/stopAlert'), lab.models.Trip, require('../../src/models/notification')]) await Model.deleteMany({});
    await lab.models.Passenger.updateMany({}, { $unset: { lastKnownLocation: 1, lastSeenAt: 1 } });
    await lab.models.Driver.updateOne({ _id: lab.ids.driver }, { status: 'active', operatingMode: req.body.terminal ? 'terminal_queue' : 'route' });
    if (!req.body.noTrip) await lab.models.Trip.create({ flowVersion: req.body.legacy ? 1 : 2, driverId: lab.ids.driver, jeepneyId: lab.ids.jeepney, routeId: lab.ids.route,
      status: 'active', active: true, acceptRequests: true, startedAt: new Date(), operatingMode: req.body.terminal ? 'terminal_queue' : 'route', terminalQueueStatus: req.body.terminal ? 'loading' : 'departed',
      terminalCheckedInAt: new Date(), terminalLoadingStartedAt: req.body.terminal ? new Date() : undefined, terminalLocation: lab.point(), terminalRadiusMeters: 100, terminalStopRef: 'Playwright Terminal' });
    await lab.models.Jeepney.updateOne({ _id: lab.ids.jeepney }, { lastKnownLocation: lab.point(), lastSeenAt: new Date(), $unset: { latestLocationOrder: 1 } });
    streamId=crypto.randomUUID(); sequence=0;
    await require('../../src/services/activeDriverContext.service').invalidateDriverActiveContext(lab.ids.driver);
    res.json({ reset: true });
  });
  controls.post('/fare', async (req,res) => { await lab.models.Route.updateOne({_id:lab.ids.route},{'fareConfig.baseAmount':req.body.amount}); res.json({updated:true}); });
  const server=controls.listen(5070,'127.0.0.1');
  fs.writeFileSync(path.resolve(__dirname,'../..',process.env.UI_LAB_ARTIFACT_DIR || 'artifacts/playwright_ui_manual_2026-10-09','lab-ready.json'), JSON.stringify({ api:lab.apiOrigin, admin:lab.webOrigin, passenger:'http://127.0.0.1:8772', driver:'http://127.0.0.1:8773', controls:'http://127.0.0.1:5070' }));
  async function stop() { server.close(); await lab.stop(); process.exit(0); }
  controls.post('/shutdown', (_req,res) => { res.json({stopping:true}); setTimeout(stop,100); });
  process.once('SIGINT',stop); process.once('SIGTERM',stop);
  console.log('ISOLATED UI LAB READY - ports 5069, 5070, 8771, 8772, 8773');
})().catch(error=>{console.error(error.stack);process.exit(1);});
