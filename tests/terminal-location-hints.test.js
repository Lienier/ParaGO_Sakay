const {test}=require('node:test');
const assert=require('node:assert/strict');
const {terminalLocationHint}=require('../src/services/terminalLocationHints.service');
const now=new Date('2026-10-18T03:00:00Z');
function driver(){return {_id:'driver',userId:{fullName:'Synthetic Driver',status:'active'},
 assignedRouteId:{_id:'route',name:'Test route',status:'active',terminal:{enabled:true,name:'Terminal',location:{type:'Point',coordinates:[121.05,14.9]},radiusMeters:75}},
 assignedJeepneyId:{_id:'jeep',plateNumber:'TEST-ONLY',status:'active',capacity:10,currentDriverId:'driver',lastSeenAt:now,lastKnownLocation:{type:'Point',coordinates:[121.05,14.9001]}}};}
test('fresh terminal location without trip is informational, never queued',()=>{
 const d=driver(),before=JSON.stringify(d),h=terminalLocationHint(d,[],{now});
 assert.equal(h.state,'Not queued');assert.equal(h.fresh,true);assert.match(h.reason,/choose a route/);assert.equal(JSON.stringify(d),before);
});
test('old or future GPS cannot confirm current terminal presence',()=>{
 for(const time of ['2026-10-17T03:00:00Z','2026-10-18T03:01:00Z','bad-date']){
  const d=driver();d.assignedJeepneyId.latestLocationOrder={capturedAt:time};
  const h=terminalLocationHint(d,[],{now});assert.equal(h.fresh,false);assert.equal(h.state,'Old location');assert.match(h.reason,/Old GPS/);
 }
});
test('queued and awaiting trips use their existing cards; on-route trips stay on-route',()=>{
 const d=driver();assert.equal(terminalLocationHint(d,[{driverId:'driver',operatingMode:'terminal_queue'}],{now}),null);
 const h=terminalLocationHint(d,[{driverId:'driver',operatingMode:'route'}],{now});assert.equal(h.state,'On route');assert.match(h.reason,/when empty/);
});
test('outside, missing and invalid positions never appear as terminal hints',()=>{
 for(const coordinates of [[121.05,14.92],[],[999,14.9],[121.05,NaN]]){
  const d=driver();d.assignedJeepneyId.lastKnownLocation.coordinates=coordinates;assert.equal(terminalLocationHint(d,[],{now}),null);
 }
 const d=driver();d.assignedRouteId=null;assert.equal(terminalLocationHint(d,[],{now}),null);
});
test('automatic waiting and manually paused arrival have different guidance',()=>{
 const d=driver();assert.match(terminalLocationHint(d,[],{now,automatic:true}).reason,/GPS arrival checks/);
 d.automaticJourneyPaused=true;assert.match(terminalLocationHint(d,[],{now,automatic:true}).reason,/choose a route/);
});
test('account, route, vehicle and assignment restrictions stay explicit',()=>{
 const d=driver();d.userId.status='deactivated';assert.match(terminalLocationHint(d,[],{now}).reason,/account/);
 d.userId.status='active';d.assignedRouteId.status='inactive';assert.match(terminalLocationHint(d,[],{now}).reason,/Route/);
 d.assignedRouteId.status='active';d.assignedJeepneyId.capacity=0;assert.match(terminalLocationHint(d,[],{now}).reason,/seats/);
 d.assignedJeepneyId.capacity=10;d.assignedJeepneyId.currentDriverId='another';assert.match(terminalLocationHint(d,[],{now}).reason,/another driver/);
});
