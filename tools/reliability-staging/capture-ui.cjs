const {chromium}=require('../../.tools/playwright/node_modules/playwright');
const fs=require('fs'),path=require('path');
const out=path.resolve(__dirname,'../../artifacts/reliability_staging_2026-10-07');
(async()=>{
 const browser=await chromium.launch();
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000}});
  await page.goto('http://127.0.0.1:8777');
  await page.waitForFunction(()=>document.querySelector('#rows').children.length>0);
  const s=await (await page.request.get('http://127.0.0.1:8777/summary.json')).json();
  const stage=s.finished?'final':'progress';
  await page.screenshot({path:path.join(out,`dashboard-${stage}.png`)});
  if(s.finished){
   await page.selectOption('#filter','failed');
   await page.screenshot({path:path.join(out,'dashboard-failures.png'),fullPage:true});
  }
  fs.writeFileSync(path.join(out,`ui-verification-${stage}.json`),JSON.stringify({capturedAt:new Date().toISOString(),status:s.status,counts:s.counts,visibleStatus:await page.locator('#status').innerText(),visibleRows:await page.locator('#rows tr').count()},null,2));
  console.log(JSON.stringify({stage,status:s.status,counts:s.counts}));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
