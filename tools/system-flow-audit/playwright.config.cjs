const path = require('node:path');
const { defineConfig } = require('../../.tools/playwright/node_modules/@playwright/test');
const output = path.resolve(__dirname, '../../artifacts/system_flow_audit_2026-10-06');
module.exports = defineConfig({ testDir: __dirname, testMatch: '**/audit.spec.cjs', workers: 1, fullyParallel: false,
  timeout: 90000, expect: { timeout: 10000 }, retries: 0,
  reporter: [['list'], ['html', { outputFolder: path.join(output, 'playwright-report'), open: 'never' }],
    ['json', { outputFile: path.join(output, 'playwright-results.json') }]],
  outputDir: path.join(output, 'playwright-results'),
  use: { browserName: 'chromium', actionTimeout: 15000, trace: 'retain-on-failure', screenshot: 'only-on-failure', serviceWorkers: 'block' } });
