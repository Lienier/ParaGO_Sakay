require('dotenv').config = () => ({parsed:{}});
Object.assign(process.env,{NODE_ENV:'test',DEPLOYMENT_ENV:'test',MONGO_URI:'mongodb://127.0.0.1/unused',REDIS_URL:'',
 JWT_SECRET:'terminal-connection-test-only',JWT_REFRESH_SECRET:'terminal-refresh-test-only',RUN_API_JOBS:'false',
 AUTOMATIC_GROUP_FLOW_ENABLED:'false',AUTOMATIC_DRIVER_LIFECYCLE_ENABLED:'false',ASYNC_LOCATION_PROCESSING_ENABLED:'false',AUTH_EMAIL_ENABLED:'false'});
const {test,before,after}=require('node:test'),assert=require('node:assert/strict');
const mongoose=require('mongoose'),request=require('supertest'),crypto=require('node:crypto'),http=require('node:http');
const path=require('node:path'),os=require('node:os');
const {MongoMemoryReplSet}=require('mongodb-memory-server');
const {io}=require('socket.io-client');
const User=require('../src/models/user'),Driver=require('../src/models/driver'),Jeep=require('../src/models/jeepney'),Route=require('../src/models/route');
const sockets=require('../src/realtime/socketServer');
let repl,app,server,adminSocket,adminToken,route,drivers=[],events=[];
const at=(lat=14.9)=>({type:'Point',coordinates:[121.05,lat]});
async function account(role){
 const u=await User.create({email:crypto.randomUUID()+'@terminal.test',fullName:'Synthetic '+role,role,status:'active'});
 const sid=crypto.randomUUID();await require('../src/models/authSession').create({_id:sid,userId:u._id,authVersion:0,expiresAt:new Date(Date.now()+3600000)});
 return {u,token:require('../src/utils/jwt').signToken({sub:String(u._id),sid})};
}
async function board(){return (await request(app).get('/api/v1/admin/hybrid-dispatch').set('Authorization','Bearer '+adminToken).expect(200)).body.data;}
async function position(driver,sequence,accuracy=5){return request(app).patch('/api/v1/drivers/location').set('Authorization','Bearer '+driver.token).set('X-App-Build','24').send({latitude:14.9,longitude:121.05,accuracyMeters:accuracy,speedMetersPerSecond:0,streamId:driver.stream,sequence,capturedAt:new Date().toISOString()}).expect(200);}
async function waitUntil(predicate){for(let n=0;n<80;n++){if(predicate())return;await new Promise(r=>setTimeout(r,25));}throw Error('Realtime event missing');}
before(async()=>{
 repl=await MongoMemoryReplSet.create({binary:{version:'8.2.6',downloadDir:path.join(os.tmpdir(),'parago-mongodb-binaries')},replSet:{count:1,ip:'127.0.0.1'}});
 await mongoose.connect(repl.getUri('terminal_connection_isolated'));
 adminToken=(await account('ADMIN')).token;
 route=await Route.create({name:'Synthetic terminal route',code:'CONNECTION-TEST',status:'active',path:{type:'LineString',coordinates:[[121.05,14.9],[121.05,14.93]]},terminal:{enabled:true,name:'Test terminal',location:at(),radiusMeters:75},stops:[{name:'Test terminal',order:0,location:at()},{name:'End',order:1,location:at(14.93)}]});
 for(let i=0;i<2;i++){
  const a=await account('DRIVER');const jeep=await Jeep.create({plateNumber:'TST '+i+'11',status:'active',capacity:6,lastKnownLocation:at(),lastSeenAt:new Date()});
  const d=await Driver.create({userId:a.u._id,status:'active',assignedJeepneyId:jeep._id,assignedRouteId:route._id});
  await Jeep.updateOne({_id:jeep._id},{$set:{currentDriverId:d._id}});drivers.push({...a,jeep,d,stream:crypto.randomUUID()});
 }
 await require('../src/models/codingHoliday').create({date:require('../src/services/operatingRules.service').manilaDate(),name:'Synthetic test exemption'});
 app=require('../src/app');await Promise.all(Object.values(mongoose.models).map(m=>m.init()));
 server=http.createServer(app);sockets.attachSocketServer(server,{corsOrigins:[]});await new Promise(r=>server.listen(0,'127.0.0.1',r));
 adminSocket=io('http://127.0.0.1:'+server.address().port,{auth:{token:adminToken},transports:['websocket'],forceNew:true});adminSocket.on('ops.changed',e=>events.push(e));
 await waitUntil(()=>adminSocket.connected);
});
after(async()=>{adminSocket?.disconnect();await sockets.closeSocketServer();if(server?.listening)await new Promise(r=>server.close(r));await mongoose.disconnect();if(repl)await repl.stop();});
test('Admin separates a fresh terminal position from an actual queue entry',async()=>{
 const b=await board();assert.equal(b.terminalQueue.length,0);assert.equal(b.awaitingTerminalArrival.length,0);
 assert.equal(b.terminalLocationHints.length,2);assert.ok(b.terminalLocationHints.every(h=>h.state==='Not queued'));
});
test('driver route intent appears in Admin; bad GPS does not check in; two valid fixes publish the queue',async()=>{
 const d=drivers[0];const created=await request(app).post('/api/v1/trips').set('Authorization','Bearer '+d.token).set('X-App-Build','24').send({jeepneyId:d.jeep._id,routeId:route._id,operatingMode:'terminal_queue',requestId:crypto.randomUUID()}).expect(201);
 assert.equal(created.body.data.status,'scheduled');let b=await board();assert.equal(b.awaitingTerminalArrival.length,1);assert.equal(b.terminalQueue.length,0);
 await position(d,1,100);b=await board();assert.equal(b.awaitingTerminalArrival[0].terminalSummary.terminalArrival.status,'poor_accuracy');assert.equal(b.terminalQueue.length,0);
 await position(d,2);b=await board();assert.equal(b.awaitingTerminalArrival[0].terminalSummary.terminalArrival.validFixes,1);
 const before=events.length;await position(d,3);await waitUntil(()=>events.length>before);
 b=await board();assert.equal(b.awaitingTerminalArrival.length,0);assert.equal(b.terminalQueue.length,1);assert.equal(b.terminalQueue[0].terminalQueueStatus,'loading');assert.equal(b.terminalLocationHints.length,1);
});
test('Admin reconnect can reconcile a queue change missed while offline',async()=>{
 adminSocket.disconnect();const d=drivers[1];
 await request(app).post('/api/v1/trips').set('Authorization','Bearer '+d.token).set('X-App-Build','24').send({jeepneyId:d.jeep._id,routeId:route._id,operatingMode:'terminal_queue',requestId:crypto.randomUUID()}).expect(201);
 await position(d,1);await position(d,2);adminSocket.connect();await waitUntil(()=>adminSocket.connected);
 const b=await board();assert.equal(b.terminalQueue.length,2);assert.equal(b.terminalQueue.filter(t=>t.terminalQueueStatus==='loading').length,1);assert.equal(b.terminalQueue.filter(t=>t.terminalQueueStatus==='waiting').length,1);
});
test('non-admin cannot read the dispatch board and driver cannot start another driver jeep',async()=>{
 await request(app).get('/api/v1/admin/hybrid-dispatch').set('Authorization','Bearer '+drivers[0].token).expect(403);
 const r=await request(app).post('/api/v1/trips').set('Authorization','Bearer '+drivers[1].token).set('X-App-Build','24').send({jeepneyId:drivers[0].jeep._id,routeId:route._id,requestId:crypto.randomUUID()});
 assert.ok([403,409].includes(r.status));
});
