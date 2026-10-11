// Real Passenger controls and API mutations; temporary loopback records only.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
process.env.UI_LAB_ARTIFACT_DIR ||= 'artifacts/full_system_release_2026-10-11/booking';
process.env.UI_LAB_AUTOMATIC_LIFECYCLE='false';
const {createLab}=require('./fixture.cjs');
const {chromium}=require('../../.tools/playwright/node_modules/playwright');
const out=path.resolve(__dirname,'../..',process.env.UI_LAB_ARTIFACT_DIR);
fs.mkdirSync(out,{recursive:true});
let lab,browser,p,context,lastQuote;const results=[],errors=[],mutations=[];
async function seen(name){await p.getByText(name,{exact:false}).or(p.getByLabel(name,{exact:false})).first().waitFor();}
async function button(name){await p.getByRole('button',{name,exact:true}).click();}
async function text(name){await p.getByText(name,{exact:true}).or(p.getByLabel(name,{exact:true})).first().click();}
async function check(name,fn){await fn();const file=String(results.length+1).padStart(2,'0')+'.png';await p.screenshot({path:path.join(out,file)});results.push({name,status:'PASS',evidence:file});console.log('PASS: '+name);}
async function type(label,value){const f=p.getByRole('textbox',{name:label,exact:true});await f.click();await p.waitForTimeout(150);await p.keyboard.press('Control+A');await p.keyboard.press('Backspace');await p.waitForTimeout(80);await p.keyboard.type(value,{delay:35});assert.equal(await f.inputValue(),value);}
async function saved(name,pickup){await button('Menu');await p.getByRole('button',{name:/^Saved Places/}).click();await seen('Saved Places');const card=p.getByRole('group',{name:new RegExp('^'+name+' ')});await card.getByRole('button',{name:pickup?'Use as pickup':'Use as unload',exact:true}).click();}
async function choose(row,name){await p.getByRole('button',{name:new RegExp('^'+row+'\\b')}).first().click();await p.getByRole('menuitem',{name,exact:true}).last().click();}
async function refresh(){await button('More');await p.getByRole('menuitem',{name:'Refresh',exact:true}).click();await p.waitForTimeout(1000);}
async function booking(){await button('Book');await text('Roadside');await seen('Seats: 6');}
(async()=>{try{
 lab=await createLab();
 await lab.models.Passenger.updateOne({_id:lab.ids.passenger},{$set:{savedPlaces:[{name:'Test pickup',key:'test-pickup',lat:14.905,lng:121.05},{name:'Test drop-off',key:'test-dropoff',lat:14.915,lng:121.05}]}});
 const trip=await lab.models.Trip.create({flowVersion:2,driverId:lab.ids.driver,jeepneyId:lab.ids.jeepney,routeId:lab.ids.route,status:'active',active:true,acceptRequests:true,startedAt:new Date(),operatingMode:'route',terminalQueueStatus:'departed'});
 browser=await chromium.launch({headless:true});context=await browser.newContext({viewport:{width:390,height:844},permissions:['geolocation'],geolocation:{latitude:14.898,longitude:121.05,accuracy:5}});p=await context.newPage();
 p.on('pageerror',e=>errors.push(e.message));p.on('console',m=>{if(/RenderFlex|overflowed by|EXCEPTION CAUGHT BY/i.test(m.text()))errors.push(m.text());});
 p.on('response',r=>{if(r.url().includes('/api/v1/pickup-requests')&&r.request().method()==='POST')mutations.push({path:new URL(r.url()).pathname,status:r.status()});});
 p.on('response',async r=>{if(r.url().endsWith('/pickup-requests/quote')&&r.status()===200)lastQuote=(await r.json()).data;});
 await p.goto('http://127.0.0.1:8772');await p.locator('flt-semantics-placeholder').evaluate(e=>e.click());
 await check('Empty login validates required fields',async()=>{await button('LOGIN');await seen('required');});
 await type('Email address',lab.accounts.passenger.email);await type('Password','Incorrect-Password-123');
 await check('Wrong password keeps the passenger signed out',async()=>{await button('LOGIN');await seen('Invalid');assert.equal(await p.getByRole('button',{name:'Menu',exact:true}).count(),0);});
 await type('Password',lab.password);await button('LOGIN');await seen('SAKAY');
 await check('Missing pickup and drop-off show an explanation without creating a booking',async()=>{await button('Book');await text('Roadside');await seen('Pins required');await p.waitForTimeout(5000);assert.equal(await require('../../src/models/pickupRequest').countDocuments(),0);});
 await check('Saved pickup and drop-off populate the next booking',async()=>{await saved('Test pickup',true);await saved('Test drop-off',false);await seen('College');});
 await booking();
 await check('Every passenger must select a drop-off before fare review',async()=>{await button('Review');await seen('Choose a drop-off for every passenger.');});
 await choose('You','College');await button('Add');await choose('Passenger 2','Market');await button('Add');await choose('Passenger 3','Market');
 await check('Group review shows individual fares and their server-calculated sum',async()=>{await button('Review');await seen('Total:');const body=await p.locator('body').innerText();assert.ok(body.includes('Fare:'));assert.equal(lastQuote.members.length,3);assert.equal(lastQuote.regularTotal,lastQuote.members.reduce((sum,m)=>sum+m.fareSnapshot.amount,0));assert.ok(body.includes(lastQuote.regularTotal.toFixed(2)));for(const m of lastQuote.members)assert.ok(body.includes(m.fareSnapshot.amount.toFixed(2)));assert.equal(await require('../../src/models/pickupRequest').countDocuments(),0);});
 await check('Unavailable quote service preserves the selections for retry',async()=>{await button('Remove');await p.route('**/pickup-requests/quote',r=>r.fulfill({status:503,contentType:'application/json',body:JSON.stringify({success:false,message:'Test quote unavailable'})}));await button('Review');await seen('Test quote unavailable');await seen('Market');await p.unroute('**/pickup-requests/quote');});
 await button('Review');await p.getByRole('button',{name:'Book',exact:true}).waitFor();
 await check('Changed fares require another review and do not create a hidden booking',async()=>{await lab.models.Route.updateOne({_id:lab.ids.route},{$set:{'fareConfig.baseAmount':23}});await button('Book');await seen('Review the updated quote');assert.equal(await require('../../src/models/pickupRequest').countDocuments(),0);});
 await button('Review');await button('Book');
 await check('A group submission creates one reserved booking and no driver acknowledgement step',async()=>{await seen('Waiting');const items=await require('../../src/models/pickupRequest').find().lean();assert.equal(items.length,1);assert.equal(items[0].members.length,2);assert.equal(items[0].partySize,2);assert.equal(items[0].status,'pending');assert.equal(items[0].flowVersion,2);assert.equal(await p.getByRole('button',{name:'Group ready',exact:true}).count(),0);});
 await check('Booking survives a page reload without a duplicate',async()=>{await p.reload();await p.locator('flt-semantics-placeholder').evaluate(e=>e.click());await seen('Waiting');assert.equal(await require('../../src/models/pickupRequest').countDocuments(),1);});
 await check('Cancel returns reserved seats and makes booking available again',async()=>{await button('Cancel');const confirm=p.getByRole('button',{name:'Cancel request',exact:true});if(await confirm.count())await confirm.click();await seen('Book');const item=await require('../../src/models/pickupRequest').findOne().lean();assert.equal(item.status,'cancelled');const state=await lab.models.Trip.findById(trip._id).lean();assert.equal(state.reservedCount||0,0);});
 await p.setViewportSize({width:320,height:740});
 // A cancelled/reloaded journey correctly clears its draft map pins.
 await saved('Test pickup',true);await saved('Test drop-off',false);
 await check('Narrow screen keeps booking controls usable',async()=>{await booking();await choose('You','College');await button('Review');await seen('Total:');const b=await p.getByRole('button',{name:'Book',exact:true}).boundingBox();assert.ok(b&&b.x>=0&&b.x+b.width<=320);assert.deepEqual(errors,[]);});
 await button('Cancel');await button('More');await p.getByRole('menuitem',{name:'Log out',exact:true}).click();
 const confirm=p.getByRole('button',{name:'Log out',exact:true});if(await confirm.count())await confirm.click();
 await check('Logout clears the authenticated passenger screen',async()=>{await p.getByRole('textbox',{name:'Email address',exact:true}).waitFor();assert.equal(await p.getByRole('button',{name:'Book',exact:true}).count(),0);});
 }catch(e){console.error(e.stack);results.push({name:e.message,status:'FAIL'});process.exitCode=1;if(p){await p.screenshot({path:path.join(out,'failure.png')});fs.writeFileSync(path.join(out,'failure-aria.txt'),await p.locator('body').ariaSnapshot());}}
 finally{fs.writeFileSync(path.join(out,'browser-results.json'),JSON.stringify(results,null,2));fs.writeFileSync(path.join(out,'page-errors.json'),JSON.stringify(errors,null,2));fs.writeFileSync(path.join(out,'mutations.json'),JSON.stringify(mutations,null,2));if(browser)await browser.close();if(lab)await lab.stop();}
})();
