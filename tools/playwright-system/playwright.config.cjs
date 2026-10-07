const path = require('node:path');
const { defineConfig } = require('../../.tools/playwright/node_modules/@playwright/test');
const output = path.resolve(__dirname, '../../artifacts/playwright_system_test_2026-10-06');
module.exports = defineConfig({
  testDir: __dirname, testMatch: '**/*.spec.cjs', fullyParallel: false, workers: 1,
  timeout: 90000, expect: { timeout: 15000 }, retries: 0,
  reporter: [['list'], ['html', { outputFolder: path.join(output, 'html-report'), open: 'never' }], ['json', { outputFile: path.join(output, 'results.json') }]],
  outputDir: path.join(output, 'test-results'),
  use: { browserName: 'chromium', actionTimeout: 15000, viewport: { width: 1440, height: 1000 }, trace: 'retain-on-failure', screenshot: 'only-on-failure', video: 'retain-on-failure', serviceWorkers: 'block' },
});
