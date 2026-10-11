const fs=require('fs'),path=require('path');
const out=path.resolve(__dirname,'../..',process.env.RELIABILITY_ARTIFACT_DIR||'artifacts/reliability_staging_2026-10-07');
module.exports=class {
 onTestEnd(test,result){
  const value={suite:process.env.RELIABILITY_SUITE,title:test.title,status:result.status,durationMs:result.duration,retry:result.retry,at:new Date().toISOString(),errors:result.errors.map(e=>e.message||'').join('\n')};
  fs.appendFileSync(path.join(out,process.env.RELIABILITY_SUITE==='recovery-recheck'?'rechecks.ndjson':'cases.ndjson'),JSON.stringify(value)+'\n');
 }
};
