// Fixture-only records for manual browser cases; refuses every non-loopback URI.
require('./fixture.cjs');
const mongoose = require('mongoose');
const uri = process.argv[2], mode = process.argv[3];
if (!/^mongodb:\/\/127\.0\.0\.1:\d+\/playwright_ui_manual_isolated_staging$/.test(uri || '')) throw Error('Only the isolated UI fixture database is allowed');
(async () => {
  await mongoose.connect(uri);
  const User=require('../../src/models/user'), Driver=require('../../src/models/driver'), Passenger=require('../../src/models/passenger');
  const Trip=require('../../src/models/tripSession'), Pickup=require('../../src/models/pickupRequest'), Ride=require('../../src/models/rideSession');
  const original=await User.findOne({email:'driver.playwright@example.test'});
  if (!original) throw Error('Synthetic fixture identity missing');
  if (mode==='drivers') {
    for(let i=1;i<=9;i++) {
      const email=`pagination-${i}.playwright@example.test`;
      if(await User.exists({email})) continue;
      const user=await User.create({email,fullName:`Synthetic Pagination Driver ${i}`,role:'DRIVER',status:'active',passwordHash:original.passwordHash});
      await Driver.create({userId:user._id,status:'inactive',employeeNumber:`UI-${i}`});
    }
    console.log('Added synthetic driver rows for real UI pagination');
  } else if (mode==='legacy') {
    const user=await User.findOne({email:'passenger.playwright@example.test'}), passenger=await Passenger.findOne({userId:user._id});
    const trip=await Trip.findOne({status:'active'});
    if(!trip || trip.flowVersion!==1) throw Error('Reset a legacy trip first');
    const point=lat=>({type:'Point',coordinates:[121.05,lat]});
    const booking=await Pickup.create({flowVersion:1,passengerId:passenger._id,tripSessionId:trip._id,routeId:trip.routeId,status:'completed',partySize:1,pickupType:'roadside',stopRef:'Playwright Terminal',pickupLocation:point(14.9),destinationStopRef:'College',destinationLocation:point(14.915),expiresAt:new Date(Date.now()+3600000)});
    await Ride.create({flowVersion:1,passengerId:passenger._id,tripSessionId:trip._id,pickupRequestId:booking._id,status:'onboard',partySize:1,boardedCount:1,remainingCount:1,boardedAt:new Date(),boardingStopRef:'Playwright Terminal',boardingLocation:point(14.9),destinationStopRef:'College',destinationLocation:point(14.915)});
    await Trip.updateOne({_id:trip._id},{occupancyCount:1});
    console.log('Added one existing legacy ride for UI compatibility completion');
  } else throw Error('Unknown fixture case');
  await mongoose.disconnect();
})().catch(e=>{console.error(e.message);process.exitCode=1;});
