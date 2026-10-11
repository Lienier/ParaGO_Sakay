// Presentation checks against disposable local records; never uses the live DB.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
process.env.UI_LAB_ARTIFACT_DIR ||= 'artifacts/mobile_ui_simplified_2026-10-09';
process.env.UI_LAB_AUTOMATIC_LIFECYCLE = 'true';
const { createLab } = require('./fixture.cjs');
const { chromium } = require('../../.tools/playwright/node_modules/playwright');
const out = path.resolve(__dirname, '../..', process.env.UI_LAB_ARTIFACT_DIR);
const results = [], errors = [];
const autoDropoff = process.env.AUTOMATIC_DROPOFF_UI_REVIEW === '1';
let lab, browser, passenger, driver;
async function check(name, fn, evidence) {
  await fn(); results.push({name, status:'PASS', evidence}); console.log('PASS: '+name);
}
async function shot(page, name) { await page.screenshot({path:path.join(out,name)}); }
async function activate(page) {
  const placeholder=page.locator('flt-semantics-placeholder');
  if(await placeholder.count()) await placeholder.evaluate(el=>el.click());
}
async function seen(page, text) {
  await activate(page);
  await page.getByText(text, {exact:false}).or(page.getByLabel(text,{exact:false})).first().waitFor();
}
async function clickText(page,text) { await activate(page); await page.getByText(text,{exact:true}).or(page.getByLabel(text,{exact:true})).first().click(); }
async function type(page, locator, value) {
  await locator.click(); await page.waitForTimeout(150); await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace'); await page.waitForTimeout(80);
  await page.keyboard.type(value,{delay:35}); assert.equal(await locator.inputValue(),value);
}
async function login(page,role,port) {
  page.on('pageerror',e=>errors.push({role,error:e.message}));
  page.on('console',m=>{if (/overflowed by|RenderFlex|EXCEPTION CAUGHT BY/i.test(m.text())) errors.push({role,error:m.text()});});
  await page.goto('http://127.0.0.1:'+port);
  await page.locator('flt-semantics-placeholder').evaluate(el=>el.click());
  await type(page,page.getByRole('textbox',{name:'Email address'}),lab.accounts[role].email);
  await type(page,page.getByRole('textbox',{name:'Password',exact:true}),lab.password);
  await page.getByRole('button',{name:'LOGIN',exact:true}).click();
  await seen(page,role==='driver'?'Drive':'SAKAY');
}
async function refresh(page) {
  await activate(page);
  await page.getByRole('button',{name:'More',exact:true}).click(); await page.getByRole('menuitem',{name:'Refresh',exact:true}).click();
  await page.waitForTimeout(700);
}
async function expandRide() {
  await activate(passenger);
  const show = passenger.getByRole('button',{name:'Show ride',exact:true});
  if (await show.count()) { await show.click(); }
  else { await passenger.getByRole('button',{name:'Ride',exact:true}).click(); await show.click(); }
  await passenger.waitForTimeout(350);
}
async function openDetails(page) {
  const height=page.viewportSize().height;
  const session=await page.context().newCDPSession(page);
  await session.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:180,y:height-155}]});
  for(let step=1;step<=25;step++) {
    await session.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:180,y:height-155+(170-(height-155))*step/25}]});
    await page.waitForTimeout(16);
  }
  await session.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  await session.detach();
  await page.waitForTimeout(400);
}
async function passengersDetails(page) {
  await activate(page);
  const button=page.getByRole('button',{name:/^Passengers/});
  if(await button.count()) { await button.click(); return; }
  // Flutter merges the Driver card and its expansion into one semantic group.
  const group=page.getByRole('group',{name:/^Passengers/});
  const bounds=await group.boundingBox();
  assert.ok(bounds,'Passenger details must have an accessible group');
  await group.click({position:{x:50,y:bounds.height-30}});
}
async function actionInView(page,name) {
  const bounds=await page.getByRole('button',{name,exact:true}).boundingBox();
  assert.ok(bounds && bounds.y>=0 && bounds.y+bounds.height<=page.viewportSize().height,`${name} must fit in the visible panel`);
}
async function swipeNotice(page, locator, direction = 1) {
  const bounds = await locator.boundingBox();
  assert.ok(bounds, 'Notice must be visible before swiping');
  const session = await page.context().newCDPSession(page);
  const startX = direction > 0 ? 60 : page.viewportSize().width - 60;
  const y = bounds.y + bounds.height / 2;
  await session.send('Input.dispatchTouchEvent', {type:'touchStart',touchPoints:[{x:startX,y}]});
  for(let i=1;i<=15;i++) {
    await session.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:startX+direction*300*i/15,y}]});
    await page.waitForTimeout(16);
  }
  await session.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  await session.detach();
}
(async()=>{
  try {
    lab=await createLab();
    if(process.env.GLASS_UI_REVIEW) await require('../../src/models/announcement').create({
      title:'Route update',body:'The terminal is open. Keep your phone near your jeep.',category:'general',
      severity:'warning',status:'published',revision:1,audiences:['PASSENGER','DRIVER'],
      startsAt:new Date(Date.now()-60000),publishedAt:new Date(),
      createdByAdminId:lab.accounts.admin._id,updatedByAdminId:lab.accounts.admin._id});
    const trip=await lab.models.Trip.create({flowVersion:2,driverId:lab.ids.driver,jeepneyId:lab.ids.jeepney,routeId:lab.ids.route,
      status:'active',active:true,acceptRequests:true,startedAt:new Date(),operatingMode:'route',terminalQueueStatus:'departed'});
    browser=await chromium.launch({headless:true});
    // Organizer stays outside the boarding radius while inspecting the waiting UI.
    const contexts=await Promise.all([14.898,14.9].map(latitude=>browser.newContext({viewport:{width:390,height:844},geolocation:{latitude,longitude:121.05},permissions:['geolocation']})));
    passenger=await contexts[0].newPage(); driver=await contexts[1].newPage();
    await login(passenger,'passenger',8772); await login(driver,'driver',8773);
    await check('Passenger home uses a compact toolbar and short booking labels',async()=>{
      await seen(passenger,'Book'); await seen(passenger,'Pickup'); await seen(passenger,'Drop-off');
      assert.equal(await passenger.getByText('Transit Flow',{exact:true}).count(),0);
      await shot(passenger,'01-passenger-home.png');
    },'01-passenger-home.png');
    await check('Refresh and logout remain accessible in More',async()=>{
      await passenger.getByRole('button',{name:'More',exact:true}).click(); await seen(passenger,'Refresh'); await seen(passenger,'Log out');
      await shot(passenger,'02-passenger-menu.png'); await passenger.getByRole('menuitem',{name:'Refresh',exact:true}).click();
    },'02-passenger-menu.png');
    await check('Driver map has one compact status panel',async()=>{
      await seen(driver,'Playwright Main Route');
      await seen(driver,'Onboard'); await seen(driver,'Pickup'); await seen(driver,'Para'); await seen(driver,'Trip');
      assert.equal(await driver.getByText('Focused trip snapshot',{exact:true}).count(),0);
      await shot(driver,'03-driver-map.png');
    },'03-driver-map.png');
    await check('Driver fallback controls are hidden until expanded; End still requires confirmation',async()=>{
      await clickText(driver,'Trip'); await seen(driver,'Seats');
      if(process.env.GLASS_UI_REVIEW) await shot(driver,'12-driver-glass-sheet.png');
      assert.equal(await driver.getByText('End',{exact:true}).count(),0);
      await clickText(driver,'Controls'); await seen(driver,'End'); await shot(driver,'04-driver-controls.png');
      if(autoDropoff) {
        for(const [label,count] of [['Add 5',5],['Remove 5',0],['Add 3',3],['Remove 3',0],['Add 1',1],['Remove 1',0]]) {
          await driver.getByRole('button',{name:label,exact:true}).click();
          for(let i=0;i<50;i++) {
            const state=await lab.models.Trip.findById(trip._id).lean();
            if(state.manualOccupancyCount===count) break;
            if(i===49) throw Error('Walk-in count did not reach '+count);
            await driver.waitForTimeout(100);
          }
          await driver.waitForTimeout(1200);
          if(count===3) await shot(driver,'22-driver-bulk-walkins.png');
        }
        await openDetails(driver);
      }
      await clickText(driver,'End'); await seen(driver,'End this trip?'); await clickText(driver,'Cancel');
      await driver.waitForTimeout(400);
      await driver.mouse.click(180,80);
      await driver.waitForTimeout(400);
      await driver.getByRole('button',{name:'More',exact:true}).waitFor();
    },'04-driver-controls.png');
    // Seed display states only. These checks do not claim to test GPS boarding.
    const members=[['You','College',14.915,17],['Passenger 2','Market',14.925,22],['Passenger 3','Nearby Stop',14.9253,22]].map((m,i)=>({
      memberId:String(i+1),organizer:i===0,label:m[0],destinationStopRef:m[1],destinationLocation:lab.point(m[2]),
      fareSnapshot:{boardingStopRef:'Playwright Terminal',boardingStopOrder:0,boardingFare:0,destinationStopRef:m[1],destinationStopOrder:i+1,destinationFare:m[3],amount:m[3]},status:'reserved'}));
    const Pickup=require('../../src/models/pickupRequest'), Ride=require('../../src/models/rideSession');
    const booking=await Pickup.create({flowVersion:2,members,passengerId:lab.ids.passenger,tripSessionId:trip._id,routeId:lab.ids.route,
      status:'pending',pickupType:'roadside',stopRef:'Playwright Terminal',pickupLocation:lab.point(),destinationStopRef:'College',destinationLocation:lab.point(14.915),expiresAt:new Date(Date.now()+3600000)});
    await refresh(passenger); await expandRide();
    await check('Waiting group shows pickup, destinations, total and Cancel; pin tools are hidden',async()=>{
      await seen(passenger,'Waiting · Auto boarding'); await seen(passenger,'PHP 61');
      assert.equal(await passenger.getByText('Book',{exact:true}).count(),0);
      assert.equal(await passenger.getByText('Clear',{exact:true}).count(),0);
      await seen(passenger,'Cancel'); await actionInView(passenger,'Cancel'); await shot(passenger,'05-passenger-waiting.png');
    },'05-passenger-waiting.png');
    await check('Passenger details expand to individual fares',async()=>{
      await openDetails(passenger); await passengersDetails(passenger); await seen(passenger,'Passenger 3: Nearby Stop'); await seen(passenger,'Total: ₱61.00');
      await shot(passenger,'06-group-details.png'); await passengersDetails(passenger);
    },'06-group-details.png');
    const onboard=members.map((m,i)=>({...m,status:i===0?'completed':'onboard',boardedAt:new Date(),...(i===0?{completedAt:new Date()}: {})}));
    booking.status='completed';await booking.save();
    const seededRide = await Ride.create({flowVersion:2,members:onboard,passengerId:lab.ids.passenger,tripSessionId:trip._id,pickupRequestId:booking._id,
      status:'onboard',boardedAt:new Date(),boardingMethod:'auto_proximity',boardingStopRef:'Playwright Terminal',boardingLocation:lab.point(),
      destinationStopRef:'College',destinationLocation:lab.point(14.915),canSendStopAlert:true});
    await lab.models.Trip.updateOne({_id:trip._id},{occupancyCount:2});
    await refresh(passenger); await refresh(driver);
    await check(autoDropoff ? 'Passenger drop-offs are automatic with no member picker' : 'Organizer-first ride keeps remaining count and manual correction under Controls',async()=>{
      await expandRide();
      await seen(passenger,'2 onboard'); await seen(passenger,'Para');
      await actionInView(passenger,'Para');
      assert.equal(await passenger.getByText('Fix drop-off',{exact:true}).count(),0);
      await openDetails(passenger);
      if(autoDropoff) {
        await seen(passenger,'Auto drop-off'); await seen(passenger,'Next: Market');
        assert.equal(await passenger.getByText('Who got off?',{exact:true}).count(),0);
        assert.equal(await passenger.getByRole('button',{name:'Controls',exact:true}).count(),0);
        await shot(passenger,'07-automatic-dropoff.png');
      } else {
        await clickText(passenger,'Controls'); await clickText(passenger,'Fix drop-off'); await seen(passenger,'Who got off?');
        assert.equal(await passenger.getByRole('checkbox').count(),2);
        await shot(passenger,'07-dropoff-correction.png'); await clickText(passenger,'Cancel');
      }
      await expandRide();
      await shot(passenger,'08-passenger-ride.png');
    },'08-passenger-ride.png');
    await check('Driver drop-offs retain fares and correction while maps fit 320px screens',async()=>{
      await clickText(driver,'Drop-offs'); await seen(driver,'Fix drop-off'); await passengersDetails(driver);
      await seen(driver,'Passenger 3: Nearby Stop'); await shot(driver,'09-driver-dropoffs.png');
      await clickText(driver,'Drive'); await driver.setViewportSize({width:320,height:740}); await passenger.setViewportSize({width:320,height:740});
      await expandRide(); await actionInView(passenger,'Para');
      await shot(driver,'10-driver-320.png'); await shot(passenger,'11-passenger-320.png'); assert.deepEqual(errors,[]);
    },'10-driver-320.png');
    if(process.env.GLASS_UI_REVIEW) {
      await passenger.setViewportSize({width:390,height:844});
      await driver.setViewportSize({width:390,height:844});
      await check('Realtime message popups wrap text on both apps',async()=>{
        const { publishNotification }=require('../../src/services/notificationPublisher');
        for(const role of ['passenger','driver']) await publishNotification({userId:lab.accounts[role]._id,
          type:'route_notice',title:'Ready',body:'Your route is ready. Check your jeep and drop-off before boarding.'});
        for(const [role,page] of [['passenger',passenger],['driver',driver]]) {
          await seen(page,'Ready: Your route is ready.');
          await shot(page,`13-${role}-glass-message.png`);
        }
      },'13-passenger-glass-message.png');
      await check('Passenger notice sheet and Driver notices show readable messages',async()=>{
        await refresh(passenger); await refresh(driver);
        await passenger.getByRole('button',{name:/^Notices(?: \d+)?$/}).click();
        await seen(passenger,'Route update'); await seen(passenger,'Ready');
        await shot(passenger,'14-passenger-glass-notices.png');
        await clickText(driver,'Notices'); await seen(driver,'Route update'); await seen(driver,'Ready');
        await shot(driver,'15-driver-glass-notices.png');
        assert.deepEqual(errors,[]);
      },'14-passenger-glass-notices.png');
      if(process.env.GREEN_GLASS_UI_REVIEW === '1') {
        await passenger.mouse.click(180,30); await passenger.waitForTimeout(400);
        await clickText(driver,'Drive');
        const { publishNotification }=require('../../src/services/notificationPublisher');
        async function publish(title) {
          for(const role of ['passenger','driver']) await publishNotification({userId:lab.accounts[role]._id,
            type:'route_notice',title,body:'Your jeep is ready.'});
        }
        await check('Passenger and Driver popups disappear after five seconds',async()=>{
          await publish('Timed notice');
          for(const [role,page] of [['passenger',passenger],['driver',driver]]) {
            await seen(page,'Timed notice: Your jeep is ready.');
            await shot(page,`16-${role}-timed-notice.png`);
          }
          await Promise.all([passenger,driver].map(page=>page.getByText('Timed notice: Your jeep is ready.',{exact:true}).waitFor({state:'hidden',timeout:7000})));
          await shot(passenger,'17-passenger-after-timeout.png');
          await shot(driver,'17-driver-after-timeout.png');
        },'16-passenger-timed-notice.png');
        await check('Passenger swipes a popup right and Driver swipes it left',async()=>{
          await publish('Swipe notice');
          for(const [role,page,direction] of [['passenger',passenger,1],['driver',driver,-1]]) {
            const notice=page.getByText('Swipe notice: Your jeep is ready.',{exact:true}).last();
            await seen(page,'Swipe notice: Your jeep is ready.');
            await swipeNotice(page,notice,direction);
            await notice.waitFor({state:'hidden',timeout:2000});
            await shot(page,`18-${role}-after-swipe.png`);
          }
          assert.deepEqual(errors,[]);
        },'18-passenger-after-swipe.png');
        await check('Controls text and full-width buttons fit both 320-pixel apps',async()=>{
          await driver.setViewportSize({width:320,height:740});
          await passenger.setViewportSize({width:320,height:740});
          await clickText(driver,'Trip'); await clickText(driver,'Controls');
          await shot(driver,'19-driver-controls-320.png');
          await openDetails(driver); await shot(driver,'20-driver-controls-scroll-320.png');
          await passenger.getByRole('button',{name:'Ride',exact:true}).waitFor();
          await openDetails(passenger);
          if(autoDropoff) {
            await seen(passenger,'Auto drop-off');
            assert.equal(await passenger.getByText('Who got off?',{exact:true}).count(),0);
          } else {
            await clickText(passenger,'Controls'); await seen(passenger,'Fix drop-off');
          }
          await shot(passenger,'21-passenger-controls-320.png');
          assert.deepEqual(errors,[]);
        },'19-driver-controls-320.png');
      }
    }
    if(autoDropoff) {
      await driver.mouse.click(160,30); await driver.waitForTimeout(400);
      await openDetails(passenger);
      const { processRide } = require('../../src/services/memberUnloading.service');
      const origin = Date.now(); let sequence = 0;
      async function stopped(latitude, offsets, nowOffset) {
        for(const offset of offsets) await processRide({rideId:seededRide._id,
          observation:{streamId:'controlled-dropoffs',sequence:++sequence,
            capturedAt:new Date(origin+offset), latitude, longitude:121.05,
            accuracyMeters:5, speedMetersPerSecond:0}, now:new Date(origin+nowOffset)});
      }
      await check('GPS arrival unloads the reached member and advances the next drop-off without selection',async()=>{
        await stopped(14.925,[-10000,-5000,0],0);
        await seen(passenger,'Next: Nearby Stop'); await seen(passenger,'1 onboard');
        const state=await Ride.findById(seededRide._id).lean();
        assert.equal(state.members[1].status,'completed'); assert.equal(state.members[2].status,'onboard');
        assert.equal(state.remainingCount,1);
        await shot(passenger,'23-passenger-next-dropoff.png');
        await stopped(14.925,[1000,6000,11000],11000);
        assert.equal((await Ride.findById(seededRide._id).lean()).remainingCount,1);
      },'23-passenger-next-dropoff.png');
      await check('Arrival at the final separate stop completes the group automatically',async()=>{
        await stopped(14.9253,[12000,17000,22000],22000);
        const state=await Ride.findById(seededRide._id).lean();
        assert.equal(state.status,'completed'); assert.equal(state.remainingCount,0);
        assert.ok(state.members.every(m=>m.status==='completed'));
        await seen(passenger,'Book');
        assert.equal(await passenger.getByText('Auto drop-off',{exact:true}).count(),0);
        await shot(passenger,'24-passenger-completed.png'); assert.deepEqual(errors,[]);
      },'24-passenger-completed.png');
    }
    for (const context of contexts) await context.close();
  } catch(e) {
    console.error(e.stack);results.push({name:e.message,status:'FAIL'});process.exitCode=1;
    for(const [name,page] of [['passenger',passenger],['driver',driver]]) if(page && !page.isClosed()) {
      await shot(page,`failure-${name}.png`);fs.writeFileSync(path.join(out,`failure-${name}-dom.txt`),await page.locator('body').innerText());
      fs.writeFileSync(path.join(out,`failure-${name}-aria.txt`),await page.locator('body').ariaSnapshot());
    }
  } finally {
    fs.writeFileSync(path.join(out,'browser-results.json'),JSON.stringify(results,null,2));
    fs.writeFileSync(path.join(out,'page-errors.json'),JSON.stringify(errors,null,2));
    if(browser)await browser.close(); if(lab)await lab.stop();
  }
})();
