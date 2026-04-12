#!/usr/bin/env node
/**
 * Opens every http(s) link in README.md in Chromium and records final HTTP status.
 * Run: npm install && npx playwright install chromium && npm run verify:readme-links
 */
import { chromium } from "playwright";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const readmePath = path.join(__dirname, "..", "README.md");
const readme = fs.readFileSync(readmePath, "utf8");
const urls = [
  ...new Set(
    [...readme.matchAll(/\[[^\]]+\]\((https?:\/\/[^)]+)\)/g)].map((m) => m[1].trim())
  ),
];

const browser = await chromium.launch({ headless: false });
const page = await browser.newPage();

const soft403 = [];
const failed = [];
const ok = [];

for (const url of urls) {
  try {
    const response = await page.goto(url, {
      // `commit` avoids timeouts on heavy or archived pages that never reach domcontentloaded.
      waitUntil: "commit",
      timeout: 35000,
    });
    const status = response?.status() ?? 0;
    if (status >= 200 && status < 400) {
      ok.push({ url, status });
    } else if (status === 403) {
      soft403.push({ url, status });
    } else {
      failed.push({ url, status });
    }
  } catch (e) {
    failed.push({ url, error: String(e.message || e) });
  }
}

await browser.close();

console.log(`Checked ${urls.length} URLs from README.md\n`);
console.log(`OK (${ok.length}):`);
ok.forEach(({ url, status }) => console.log(`  ${status} ${url}`));
console.log(`\n403 (${soft403.length}) — page may still render in a normal browser; re-check manually if unsure:`);
soft403.forEach(({ url, status }) => console.log(`  ${status} ${url}`));
console.log(`\nFailed (${failed.length}):`);
failed.forEach((f) => console.log(`  ${JSON.stringify(f)}`));

const hardFail = failed.length > 0;
if (hardFail) {
  console.error("\nFix failing URLs above (404/timeout/errors).");
}
process.exit(hardFail ? 1 : 0);
