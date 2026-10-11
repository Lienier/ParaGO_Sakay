const {test,expect}=require('../../.tools/playwright/node_modules/@playwright/test');
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const {io}=require('socket.io-client');
const {createLab}=require('./fixture.cjs');
const out=path.resolve(__dirname,'../..',process.env.RELIABILITY_ARTIFACT_DIR||'artifacts/reliability_staging_2026-10-07');
let lab,api,phase='',sequence=1;
const sessions={},pause=ms=>new Promise(r=>setTimeout(r,ms));
const models=()=>({Pickup:require('../../src/models/pickupRequest'),Ride:require('../../src/models/rideSession'),Alert:require('../../src/models/stopAlert'),Notification:require('../../src/models/notification')});
async function call(method,route,actor,data,status=200){
 const start=performance.now();
 const r=await api[method]('/api/v1'+route,{headers:actor?{Authorization:'Bearer '+(actor==='admin'?lab.adminToken:sessions[actor].token)}:{},...(data===undefined?{}:{data})});
 const body=await r.json();
 fs.appendFileSync(path.join(out,process.env.RELIABILITY_SUITE==='recovery-recheck'?'recheck-requests.ndjson':'requests.ndjson'),JSON.stringify({at:new Date().toISOString(),scenario:phase,method,route:route.replace(/[a-f0-9]{24}/g,':id'),status:r.status(),expected:status,ms:+(performance.now()-start).toFixed(2)})+'\n');
 if(status!==null)expect(r.status(),method+' '+route+': '+JSON.stringify(body)).toBe(status);
 return {status:r.status(),body};
}
const data=async(...args)=>(await call(...args)).body.data;
async function reset(){
 // This fixture never loads .env and only creates a temporary loopback database.
 expect(require('mongoose').connection.host).toBe('127.0.0.1');
 await Promise.all([...Object.values(models()),lab.models.Trip].map(m=>m.deleteMany({})));
 await lab.models.Passenger.updateMany({},{$unset:{lastKnownLocation:1,lastSeenAt:1}});
 await lab.models.Driver.updateOne({_id:lab.ids.driver},{$set:{status:'active',operatingMode:'route',terminalQueueStatus:'off_queue'},$unset:{terminalQueueNumber:1}});
 await lab.models.Jeepney.updateOne({_id:lab.ids.jeepney},{$set:{capacity:6,status:'active',lastKnownLocation:lab.point(),lastSeenAt:new Date()},$unset:{latestLocationOrder:1}});
 await lab.models.Route.updateOne({_id:lab.ids.route},{$set:{status:'active'}});
 sequence=1;
}
async function gps(latitude,streamId){return call('patch','/drivers/me/location','driver',{latitude,longitude:121.05,accuracyMeters:5,streamId,sequence:sequence++,capturedAt:new Date().toISOString()});}
async function roadside(){
 await lab.models.Driver.updateOne({_id:lab.ids.driver},{$set:{operatingMode:'route'}});
 const trip=await lab.models.Trip.create({driverId:lab.ids.driver,jeepneyId:lab.ids.jeepney,routeId:lab.ids.route,status:'active',operatingMode:'route',terminalQueueStatus:'departed',acceptRequests:true,startedAt:new Date()});
 return String(trip._id);
}
function pickup(type='roadside',count=1){return {routeId:lab.ids.route,pickupType:type,partySize:count,stopRef:'Roadside pickup',pickupLocation:lab.point(14.905),destinationStopRef:'PW-END',destinationLocation:lab.point(14.93)};}
async function socket(actor='driver'){
 const s=io(lab.apiOrigin,{transports:['websocket'],auth:{token:sessions[actor].token},reconnection:false});
 try{await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Socket timed out')),10000);s.once('connect',()=>{clearTimeout(timer);resolve();});s.once('connect_error',e=>{clearTimeout(timer);reject(e);});});return s;}catch(e){s.disconnect();throw e;}
}
test.beforeAll(async({playwright})=>{
 test.setTimeout(120000);lab=await createLab();api=await playwright.request.newContext({baseURL:lab.apiOrigin});
 phase='fixture authentication';
 for(const actor of ['driver','otherDriver','passenger','otherPassenger'])sessions[actor]=await data('post','/auth/login-email',null,{email:lab.accounts[actor].email,password:lab.password,role:lab.accounts[actor].role});
});
test.beforeEach(async({},info)=>{phase=info.title;await reset();});
test.afterAll(async()=>{if(api)await api.dispose();if(lab)await lab.stop();});

for(let cycle=1;cycle<=30;cycle++)test(`Terminal/group journey ${String(cycle).padStart(2,'0')}/30`,async()=>{
 const stream=crypto.randomUUID();
 const trip=await data('post','/trips','driver',{jeepneyId:lab.ids.jeepney,routeId:lab.ids.route,status:'active',operatingMode:'terminal_queue'},201);
 for(let n=0;n<2;n++)await gps(14.9,stream);
 expect((await lab.models.Trip.findById(trip._id)).terminalQueueStatus).toBe('loading');
 const request=await data('post','/pickup-requests','passenger',pickup('terminal',3),201);
 await call('patch',`/pickup-requests/${request._id}/acknowledge`,'driver',{});
 await call('patch','/passengers/me/location','passenger',{lat:14.9,lng:121.05,capturedAt:new Date().toISOString()});
 await call('post',`/pickup-requests/${request._id}/group-ready`,'passenger',{});
 const mutation={count:2,requestId:crypto.randomUUID()};
 const [ride,duplicate]=await Promise.all([data('post',`/pickup-requests/${request._id}/group-board`,'driver',mutation),data('post',`/pickup-requests/${request._id}/group-board`,'driver',mutation)]);
 expect(duplicate._id).toBe(ride._id);expect(ride.remainingCount).toBe(2);
 expect(await models().Ride.countDocuments({pickupRequestId:request._id})).toBe(1);
 await call('patch',`/trips/${trip._id}/terminal/depart`,'driver',{requestId:crypto.randomUUID()});
 await call('post','/stop-alerts','passenger',{tripSessionId:trip._id,stopRef:'PW-END',location:lab.point(14.93)},201);
 expect((await lab.models.Trip.findById(trip._id)).occupancyCount).toBe(2);
 const unload={count:1,revision:0,requestId:crypto.randomUUID()};
 const results=await Promise.all([data('patch',`/ride-sessions/${ride._id}/complete`,'driver',unload),data('patch',`/ride-sessions/${ride._id}/complete`,'driver',unload)]);
 expect(results.map(r=>r.remainingCount)).toEqual([1,1]);
 await call('patch',`/ride-sessions/${ride._id}/complete`,'driver',{count:1,revision:1,requestId:crypto.randomUUID()});
 await call('patch',`/trips/${trip._id}/end`,'driver',{requestId:crypto.randomUUID()});
 expect((await models().Ride.findById(ride._id)).remainingCount).toBe(0);
 expect((await lab.models.Trip.findById(trip._id)).occupancyCount).toBe(0);
 await pause(2500);
});
for(let cycle=1;cycle<=30;cycle++)test(`Roadside/solo journey ${String(cycle).padStart(2,'0')}/30`,async()=>{
 const trip=await roadside(),stream=crypto.randomUUID();await gps(14.9,stream);
 const cancelled=await data('post','/pickup-requests','passenger',pickup(),201);
 await call('patch',`/pickup-requests/${cancelled._id}/cancel`,'passenger',{});
 const request=await data('post','/pickup-requests','passenger',pickup(),201);
 await call('patch',`/pickup-requests/${request._id}/acknowledge`,'driver',{});
 await gps(14.905,stream);
 await call('patch','/passengers/me/location','passenger',{lat:14.905,lng:121.05,capturedAt:new Date().toISOString()});
 const payload={tripSessionId:trip,pickupRequestId:request._id,lat:14.905,lng:121.05};
 const ride=await data('post','/boarding/validate','passenger',payload);
 expect((await data('post','/boarding/validate','passenger',payload))._id).toBe(ride._id);
 expect(await models().Ride.countDocuments({pickupRequestId:request._id})).toBe(1);
 await call('post','/stop-alerts','passenger',{tripSessionId:trip,stopRef:'PW-END',location:lab.point(14.93)},201);
 await call('patch',`/ride-sessions/${ride._id}/complete`,'passenger',{});
 await call('patch',`/ride-sessions/${ride._id}/complete`,'passenger',{});
 await call('patch',`/trips/${trip}/end`,'driver',{requestId:crypto.randomUUID()});
 expect((await models().Ride.findById(ride._id)).status).toBe('completed');
 expect((await lab.models.Trip.findById(trip)).occupancyCount).toBe(0);
 await pause(2500);
});
test('Two passengers racing for the last seat never over-reserve',async()=>{
 const trip=await roadside();await lab.models.Jeepney.updateOne({_id:lab.ids.jeepney},{$set:{capacity:1}});
 const responses=await Promise.all(['passenger','otherPassenger'].map(a=>call('post','/pickup-requests',a,pickup(),null)));
 const pending=await models().Pickup.find({tripSessionId:trip,status:{$in:['pending','acknowledged']}});
 await test.info().attach('capacity race',{body:Buffer.from(JSON.stringify({statuses:responses.map(r=>r.status),reserved:pending.reduce((n,r)=>n+r.partySize,0),capacity:1})),contentType:'application/json'});
 expect(responses.filter(r=>r.status===201)).toHaveLength(1);
 expect(responses.filter(r=>r.status===409)).toHaveLength(1);
 expect(pending.reduce((n,r)=>n+r.partySize,0)).toBe(1);
});
test('Socket reconnection, HTTP listener restart and database reconnection preserve ride',async()=>{
 const trip=await roadside(),stream=crypto.randomUUID();await gps(14.9,stream);
 const request=await data('post','/pickup-requests','passenger',pickup(),201);
 await call('patch',`/pickup-requests/${request._id}/acknowledge`,'driver',{});await gps(14.905,stream);
 await call('patch','/passengers/me/location','passenger',{lat:14.905,lng:121.05,capturedAt:new Date().toISOString()});
 const ride=await data('post','/boarding/validate','passenger',{tripSessionId:trip,pickupRequestId:request._id,lat:14.905,lng:121.05});
 let s=await socket();s.disconnect();s=await socket();s.disconnect();
 const start=performance.now();await lab.restartListener();await lab.reconnectDatabase();
 const roster=await data('get',`/ride-sessions/trip/${trip}`,'driver');
 expect(roster.find(r=>r._id===ride._id).status).toBe('onboard');
 expect((await lab.models.Trip.findById(trip)).occupancyCount).toBe(1);
 const ms=performance.now()-start;
 fs.writeFileSync(path.join(out,'recovery.json'),JSON.stringify({scope:'HTTP listener restart and MongoDB client reconnect; not OS process restart',recoveryMs:ms,ridePreserved:true,occupancyPreserved:true},null,2));
 expect(ms).toBeLessThan(30000);
 s=await socket();s.disconnect();
});
test('Five-minute concurrent-user diagnostic: 5, 10, 25 and 50 users',async()=>{
 test.setTimeout(420000);
 const mongoose=require('mongoose'),User=lab.models.User,AuthSession=require('../../src/models/authSession'),signToken=require('../../src/utils/jwt').signToken;
 const virtual=[];
 for(let i=0;i<50;i++){
  const u=await User.create({email:`reliability-${i}@example.test`,fullName:`Reliability user ${i}`,role:'PASSENGER',status:'active'});
  await lab.models.Passenger.create({userId:u._id});
  const sid=crypto.randomUUID();await AuthSession.create({_id:sid,userId:u._id,authVersion:0,expiresAt:new Date(Date.now()+3600000)});
  const actor='virtual'+i;sessions[actor]={token:signToken({sub:String(u._id),role:u.role,sid})};virtual.push(actor);
 }
 const samples=[],levels=[5,10,25,50],start=Date.now();
 for(const users of levels){
  console.log(`[LOAD] ${users} concurrent authenticated users for 75 seconds`);
  const until=Date.now()+75000;
  while(Date.now()<until){
   const began=Date.now(),cpu=process.cpuUsage();
   await Promise.all(virtual.slice(0,users).map(async a=>{await call('get','/auth/me',a);await call('get','/routes',a);}));
   const ready=await api.get('/ready');expect(ready.status()).toBe(200);
   samples.push({elapsedMs:Date.now()-start,users,rssMb:process.memoryUsage().rss/1048576,heapMb:process.memoryUsage().heapUsed/1048576,cpuMicroseconds:process.cpuUsage(cpu),mongooseReadyState:mongoose.connection.readyState,readyStatus:ready.status()});
   fs.writeFileSync(path.join(out,'load-samples.json'),JSON.stringify(samples,null,2));
   await pause(Math.max(0,5000-(Date.now()-began)));
  }
 }
 console.log('[LOAD] Completed bounded five-minute diagnostic; multi-hour soak remains unexecuted.');
});
