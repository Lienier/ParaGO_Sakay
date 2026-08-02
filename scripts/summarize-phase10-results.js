const fs = require('fs');
const path = require('path');

const { rootDir } = require('./phase10-safety');

const artifactsDirectory = path.join(rootDir, 'artifacts', 'phase10');

const metricValue = (summary, name, key) =>
  Number(summary?.metrics?.[name]?.values?.[key]);

const summarizeK6 = (file, summary) => {
  const locationP95 = metricValue(summary, 'parago_location_latency', 'p(95)');
  const ordinaryP95 = metricValue(summary, 'parago_ordinary_latency', 'p(95)');
  const errorRate = metricValue(summary, 'parago_request_errors', 'rate');
  return {
    file,
    type: 'rest',
    metrics: { locationP95, ordinaryP95, errorRate },
    acceptance: {
      locationP95Below250Ms: locationP95 < 250,
      ordinaryP95Below500Ms: ordinaryP95 < 500,
      errorRateBelowOnePercent: errorRate < 0.01,
    },
  };
};

const summarizeSocket = (file, summary) => ({
  file,
  type: 'socket',
  metrics: summary.metrics,
  acceptance: summary.acceptance,
});

const compileResults = (entries) => {
  const results = entries.map(({ file, value }) =>
    file.endsWith('-rest-summary.json')
      ? summarizeK6(file, value)
      : summarizeSocket(file, value)
  );
  const checks = results.flatMap((result) => Object.values(result.acceptance));
  return {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    resultCount: results.length,
    passed: checks.length > 0 && checks.every(Boolean),
    results,
    infrastructureMetricsRequired: [
      'sustainedCpuBelow75Percent',
      'sustainedMemoryBelow80Percent',
      'redisEvictionsZero',
      'automationQueueP95Below5Seconds',
      'duplicateRideSessionsZero',
    ],
  };
};

const main = () => {
  if (!fs.existsSync(artifactsDirectory)) {
    throw new Error('No Phase 10 artifact directory exists');
  }
  const files = fs
    .readdirSync(artifactsDirectory)
    .filter((file) => /-(?:rest|socket)-summary\.json$/.test(file));
  if (!files.length) throw new Error('No Phase 10 summaries were found');
  const compiled = compileResults(
    files.map((file) => ({
      file,
      value: JSON.parse(
        fs.readFileSync(path.join(artifactsDirectory, file), 'utf8')
      ),
    }))
  );
  const output = path.join(artifactsDirectory, 'capacity-report.json');
  fs.writeFileSync(output, `${JSON.stringify(compiled, null, 2)}\n`);
  console.log(`Phase 10 capacity report written to ${output}`);
  if (!compiled.passed) process.exitCode = 1;
};

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(`Phase 10 summary failed: ${error.message}`);
    process.exitCode = 1;
  }
}

module.exports = { compileResults, summarizeK6, summarizeSocket };
