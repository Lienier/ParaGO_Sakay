const fs=require('fs'),path=require('path'),http=require('http'),{spawn}=require('child_process'),crypto=require('crypto');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'artifacts/reliability_staging_2026-10-07');
fs.mkdirSync(out,{recursive:true});
const started=new Date().toISOString(),events=[],runs=[];
const readLines=file=>fs.existsSync(file)?fs.readFileSync(file,'utf8').split(/\r?\n/).filter(Boolean).flatMap(l=>{try{return [JSON.parse(l)];}catch{return [];}}):[];
for(const name of ['cases.ndjson','requests.ndjson','terminal.log'])fs.writeFileSync(path.join(out,name),'');
const log=s=>{process.stdout.write(s+'\n');fs.appendFileSync(path.join(out,'terminal.log'),s+'\n');};
const quantile=(a,p)=>a.length?a.slice().sort((x,y)=>x-y)[Math.ceil(a.length*p)-1]:null;
let phase='Preflight',finished=false,runnerError=null,preflight={status:'pending'};
function summary(){
 const cases=readLines(path.join(out,'cases.ndjson')),requests=readLines(path.join(out,'requests.ndjson'));
 const journey=cases.filter(c=>/journey \d+\/30/.test(c.title)),failed=cases.filter(c=>c.status!=='passed');
 const timings=requests.map(r=>r.ms),valid=requests.filter(r=>r.expected!==null);
 return {started,updated:new Date().toISOString(),finished,phase,preflight,environment:'Isolated local test environment; remote staging unavailable',
  status:runnerError?'RUNNER ERROR':!finished?'RUNNING':failed.length?'FAILED':'LOCAL CHECKS PASSED; REMOTE STAGING BLOCKED',runs,runnerError,nodeVersion:process.version,
  counts:{executed:cases.length,passed:cases.filter(c=>c.status==='passed').length,failed:failed.length,journeys:journey.length,successfulJourneys:journey.filter(c=>c.status==='passed').length},
  metrics:{requests:requests.length,unexpectedStatuses:valid.filter(r=>r.status!==r.expected).length,p50Ms:quantile(timings,.5),p95Ms:quantile(timings,.95),p99Ms:quantile(timings,.99),journeySuccessPercent:journey.length?100*journey.filter(c=>c.status==='passed').length/journey.length:null},
  cases,limitations:['No cloud staging execution: configured Atlas SRV lookup fails.','Local fixture NODE_ENV=test and DEPLOYMENT_ENV=test; not cloud deployment settings.','OTP transport captured in memory; real email/FCM delivery untested.','Synthetic GPS; native phone UI and physical GPS untested.','Schedulers and async location/notification workers disabled in fixture.','Recovery tests cover HTTP listener and MongoDB client reconnection, not OS process restart.','Concurrent traffic exercises authenticated reads; booking race separately uses two passengers.','Five-minute load diagnostic is not a multi-hour soak or uptime certification.','Memory samples cover Node test/API process, not total MongoDB/Redis or cloud memory.'],
  sourceRevision:revision,applicationFilesChanged:false};
}
let revision='unknown';try{revision=require('child_process').execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();}catch{}
function update(){const s=summary();fs.writeFileSync(path.join(out,'summary.json'),JSON.stringify(s,null,2));return s;}
const dashboard=fs.readFileSync(path.join(__dirname,'dashboard.html'),'utf8');
fs.writeFileSync(path.join(out,'index.html'),dashboard);
const server=http.createServer((req,res)=>{
 const rel=decodeURIComponent(req.url.split('?')[0]);
 if(rel==='/'){res.setHeader('Content-Type','text/html');return res.end(dashboard);}
 if(rel==='/summary.json'){res.setHeader('Content-Type','application/json');res.setHeader('Cache-Control','no-store');return res.end(JSON.stringify(update()));}
 const file=path.resolve(out,'.'+rel);
 if(!file.startsWith(out+path.sep)||!fs.existsSync(file)||fs.statSync(file).isDirectory()){res.statusCode=404;return res.end('Not found');}
 const types={'.html':'text/html','.json':'application/json','.png':'image/png','.js':'application/javascript','.css':'text/css','.log':'text/plain','.md':'text/plain','.csv':'text/csv'};
 res.setHeader('Content-Type',types[path.extname(file)]||'application/octet-stream');fs.createReadStream(file).pipe(res);
});
server.listen(8777,'127.0.0.1',()=>log('[UI] http://127.0.0.1:8777 — live local reliability results'));
const timer=setInterval(update,2000);
async function run(suite){
 phase=suite;log('\n========== '+suite.toUpperCase()+' ==========' );
 fs.mkdirSync(path.join(out,suite),{recursive:true});
 const began=Date.now(),child=spawn(process.execPath,[path.join(root,'.tools/playwright/node_modules/playwright/cli.js'),'test','--config',path.join(__dirname,'playwright.config.cjs')],{cwd:root,env:{...process.env,RELIABILITY_SUITE:suite,FORCE_COLOR:'0'},stdio:['ignore','pipe','pipe']});
 for(const stream of [child.stdout,child.stderr])stream.on('data',chunk=>{const s=chunk.toString();process.stdout.write(s);fs.appendFileSync(path.join(out,'terminal.log'),s);});
 const code=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',resolve);});
 runs.push({suite,exitCode:code,durationMs:Date.now()-began});log(`[RESULT] ${suite}: exit ${code}`);update();
}
async function main(){
 log('SAKAY RELIABILITY DOCUMENTATION RUN | '+started);log('No application source fixes are part of this run.');
 const mongoose=require('mongoose'),dns=require('dns').promises;
 try{
  const b=require('../../scripts/phase10-safety').loadStagingBoundary();
  await mongoose.connect(b.stagingUri,{serverSelectionTimeoutMS:12000,autoIndex:false});await mongoose.connection.db.command({ping:1});
  preflight={status:'reachable',database:'parago_staging',writes:0};
 }catch(e){
  const checks=[];
  try{const b=require('../../scripts/phase10-safety').loadStagingBoundary();for(const ip of ['1.1.1.1','8.8.8.8']){const r=new dns.Resolver({timeout:2500,tries:1});r.setServers([ip]);try{const a=await r.resolveSrv('_mongodb._tcp.'+b.targets.staging.host);checks.push({resolver:ip,result:'found',records:a.length});}catch(err){checks.push({resolver:ip,result:err.code});}}}catch{}
  preflight={status:'blocked',reason:e.code||e.name,database:'parago_staging',writes:0,dnsChecks:checks};
 }finally{await mongoose.disconnect();}
 log('[STAGING] '+JSON.stringify(preflight));
 if(preflight.status!=='blocked')throw Error('Staging state changed: review remote test target before proceeding with fallback-only run.');
 log('[SCOPE] Executing isolated local fallback; results do not certify remote staging.');
 await run('baseline');await run('reliability');await run('faults');
 finished=true;phase='Complete';const s=update();
 const q=x=>JSON.stringify(x==null?'':x);
 fs.writeFileSync(path.join(out,'scenarios.csv'),'suite,scenario,status,duration_ms,retry\n'+s.cases.map(c=>[c.suite,c.title,c.status,c.durationMs,c.retry].map(q).join(',')).join('\n')+'\n');
 const requests=readLines(path.join(out,'requests.ndjson'));
 fs.writeFileSync(path.join(out,'requests.csv'),'timestamp,scenario,method,route,status,expected,ms\n'+requests.map(r=>[r.at,r.scenario,r.method,r.route,r.status,r.expected,r.ms].map(q).join(',')).join('\n')+'\n');
 const failures=s.cases.filter(c=>c.status!=='passed');
 const markdown=`# SAKAY reliability results\n\nStarted: ${started}\nFinished: ${new Date().toISOString()}\nSource revision: ${revision}\n\n**Remote staging BLOCKED:** Atlas lookup failed (${preflight.reason}); no staging writes occurred. The results below come from an isolated local test environment.\n\n**${s.counts.passed}/${s.counts.executed} scenarios passed; ${s.counts.failed} failed. ${s.counts.successfulJourneys}/${s.counts.journeys} repeated journeys passed.** No test retries were enabled.\n\nAPI measurements: ${s.metrics.requests} measured requests; p95 ${s.metrics.p95Ms} ms; unexpected status responses ${s.metrics.unexpectedStatuses}. Expected negative responses and capacity races are recorded separately in requests.csv; fault suite requests are outside these latency measurements.\n\n## Failures\n\n${failures.map(c=>`- ${c.suite}: ${c.title}`).join('\n')||'None.'}\n\n## Limits\n\n${s.limitations.map(x=>'- '+x).join('\n')}\n\n## Documentation\n\nOpen index.html for the dashboard; baseline/html-report/index.html, reliability/html-report/index.html and faults/html-report/index.html for Playwright evidence. terminal.log contains command output; scenarios.csv and requests.csv contain measured results. load-samples.json records local Node memory/readiness observations. recovery.json describes the exercised recovery scope.\n\nA passing local scenario does not demonstrate production availability or a passing cloud staging deployment.\n`;
 fs.writeFileSync(path.join(out,'REPORT.md'),markdown);
 fs.writeFileSync(path.join(out,'START_HERE.md'),'# Reliability documentation\n\nRun: `node tools/reliability-staging/run.cjs` from the repository root after building the admin web app and starting dedicated Redis at 127.0.0.1:6398. The runner performs a read-only remote staging preflight, then uses the local fallback only if that preflight is blocked. It never targets a remote application API.\n\nThe visible console shows each result. Browse http://127.0.0.1:8777 for live results. Ctrl+C closes the report server after the run. Each run overwrites this folder\'s test evidence; preserve it first if needed.\n\nFull scope and failures: REPORT.md.\n');
 log('\n========== DOCUMENTATION RESULT ==========' );
 log('REMOTE STAGING: BLOCKED ('+preflight.reason+')');log(`LOCAL SCENARIOS: ${s.counts.passed} passed / ${s.counts.failed} failed / ${s.counts.executed} executed`);
 log(`REPEATED JOURNEYS: ${s.counts.successfulJourneys}/${s.counts.journeys}`);log(`MEASURED REQUESTS: ${s.metrics.requests}; p95=${s.metrics.p95Ms} ms`);
 for(const c of failures)log('FAIL: '+c.title);
 log('Dashboard remains available at http://127.0.0.1:8777');clearInterval(timer);
}
main().catch(e=>{finished=true;phase='Runner error';runnerError=e.message;events.push(e.message);log('[RUNNER ERROR] '+e.message);update();clearInterval(timer);});
