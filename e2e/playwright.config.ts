import { defineConfig, devices } from "@playwright/test";

// Runs against a live app seeded with the QA tenant (bin/rails runner script/qa_tenant.rb).
// Default target is the local Compose app; override with E2E_BASE_URL.
export default defineConfig({
  testDir: "./tests",
  // The Arabic tests change the QA user's saved locale, so keep one worker.
  workers: 1,
  fullyParallel: false,
  retries: process.env.CI ? 1 : 0,
  reporter: [["list"]],
  use: {
    baseURL: process.env.E2E_BASE_URL ?? "http://localhost:3001",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    launchOptions: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
      ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH }
      : {},
  },
  outputDir: "test-results",
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"], viewport: { width: 1360, height: 900 } } },
  ],
});
