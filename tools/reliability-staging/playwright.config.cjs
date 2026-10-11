const path=require('path');
const {defineConfig}=require('../../.tools/playwright/node_modules/@playwright/test');
const out=path.resolve(__dirname,'../..',process.env.RELIABILITY_ARTIFACT_DIR||'artifacts/reliability_staging_2026-10-07');
const suite=process.env.RELIABILITY_SUITE||'baseline';
module.exports=defineConfig({testDir:__dirname,testMatch:`${suite}.spec.cjs`,workers:1,fullyParallel:false,retries:0,
 timeout:90000,expect:{timeout:15000},
 reporter:[['list'],[path.join(__dirname,'reporter.cjs')],['html',{outputFolder:path.join(out,suite,'html-report'),open:'never'}],['json',{outputFile:path.join(out,suite,'results.json')}]],
 outputDir:path.join(out,suite,'test-results'),
 use:{browserName:'chromium',viewport:{width:1440,height:1000},actionTimeout:15000,trace:'retain-on-failure',screenshot:'only-on-failure',video:'retain-on-failure',serviceWorkers:'block'}});
