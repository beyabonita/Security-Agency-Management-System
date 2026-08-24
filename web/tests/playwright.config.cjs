const { defineConfig } = require('@playwright/test');
const path = require('node:path');

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: '*.spec.js',
  fullyParallel: false,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: 'http://127.0.0.1:4173',
    browserName: 'chromium',
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'node tests/static_server.js',
    cwd: path.resolve(__dirname, '..'),
    url: 'http://127.0.0.1:4173/staff/login.html',
    timeout: 30_000,
    reuseExistingServer: !process.env.CI,
  },
});
