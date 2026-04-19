#!/usr/bin/env node
/**
 * verify-ui.mjs — Playwright-based UI verification for the pipeline.
 *
 * Usage:
 *   node scripts/verify-ui.mjs <url> [selector]
 *
 * Examples:
 *   node scripts/verify-ui.mjs http://localhost:3000/automation
 *   node scripts/verify-ui.mjs http://localhost:3000/automation '[data-testid="ai-suggest"]'
 *
 * Loads auth state from .claude/auth-state.json if it exists.
 *
 * Exit 0 = PASS, Exit 1 = FAIL
 */

import { chromium } from 'playwright';
import { existsSync, mkdirSync } from 'fs';
import { dirname } from 'path';

const [,, url, selector] = process.argv;

if (!url) {
  console.log('Usage: node scripts/verify-ui.mjs <url> [selector]');
  process.exit(1);
}

const AUTH_STATE = '.claude/auth-state.json';
const SCREENSHOT_DIR = '.claude';
const TIMEOUT = 15000;

async function verify() {
  const browser = await chromium.launch({ headless: true, channel: 'chrome' });

  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 },
  });
  const page = await context.newPage();

  // Sign in via the login form if credentials exist
  const TEST_EMAIL = process.env.TEST_EMAIL;
  const TEST_PASSWORD = process.env.TEST_PASSWORD;
  if (!TEST_EMAIL || !TEST_PASSWORD) {
    throw new Error('TEST_EMAIL and TEST_PASSWORD env vars are required');
  }

  // Navigate to login first
  const baseUrl = url.split('/').slice(0, 3).join('/');
  try {
    await page.goto(baseUrl + '/login', { waitUntil: 'networkidle', timeout: 10000 });
    const emailInput = await page.$('input[type="email"], input[name="email"]');
    if (emailInput) {
      await emailInput.fill(TEST_EMAIL);
      const passwordInput = await page.$('input[type="password"]');
      if (passwordInput) {
        await passwordInput.fill(TEST_PASSWORD);
        await page.click('button[type="submit"]');
        await page.waitForURL('**/dashboard**', { timeout: 10000 }).catch(() => {});
        // Small delay for auth cookies to settle
        await page.waitForTimeout(1000);
      }
    }
  } catch { /* login failed — will proceed unauthenticated */ }

  const consoleErrors = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });

  const pageErrors = [];
  page.on('pageerror', (err) => pageErrors.push(err.message));

  try {
    const response = await page.goto(url, { waitUntil: 'networkidle', timeout: TIMEOUT });

    if (!response) {
      console.log(`FAIL: No response from ${url}`);
      process.exit(1);
    }

    if (response.status() >= 400) {
      console.log(`FAIL: HTTP ${response.status()} from ${url}`);
      process.exit(1);
    }

    // Check for Next.js error overlay
    const errorOverlay = await page.$('#__next-build-error, [data-nextjs-dialog], .nextjs-container-errors-header');
    if (errorOverlay) {
      const errorText = await errorOverlay.textContent();
      console.log(`FAIL: Next.js error overlay: ${errorText?.substring(0, 200)}`);
      await screenshot(page, 'fail');
      process.exit(1);
    }

    if (pageErrors.length > 0) {
      console.log(`FAIL: ${pageErrors.length} uncaught error(s):`);
      pageErrors.slice(0, 3).forEach((e) => console.log(`  - ${e.substring(0, 200)}`));
      await screenshot(page, 'fail');
      process.exit(1);
    }

    if (consoleErrors.length > 0) {
      console.log(`WARNING: ${consoleErrors.length} console error(s):`);
      consoleErrors.slice(0, 3).forEach((e) => console.log(`  - ${e.substring(0, 150)}`));
    }

    // No selector = just confirm page loaded
    if (!selector) {
      console.log(`PASS: Page loaded (HTTP ${response.status()})`);
      await screenshot(page, 'pass');
      process.exit(0);
    }

    // Wait for selector
    try {
      await page.waitForSelector(selector, { state: 'attached', timeout: 5000 });
    } catch {
      console.log(`FAIL: "${selector}" not found in DOM after 5s`);

      // Debug: list available data-testid values
      if (selector.startsWith('[data-testid=')) {
        const ids = await page.evaluate(() =>
          Array.from(document.querySelectorAll('[data-testid]'))
            .map((el) => el.getAttribute('data-testid'))
            .slice(0, 20)
        );
        if (ids.length > 0) console.log(`  Available data-testids: ${ids.join(', ')}`);
      }

      await screenshot(page, 'fail');
      process.exit(1);
    }

    // Check visibility
    const element = await page.$(selector);
    const visible = await element.isVisible();

    if (!visible) {
      const debug = await page.evaluate((sel) => {
        const el = document.querySelector(sel);
        if (!el) return { reason: 'not in DOM' };
        const style = window.getComputedStyle(el);
        const rect = el.getBoundingClientRect();
        return {
          display: style.display,
          visibility: style.visibility,
          opacity: style.opacity,
          width: rect.width,
          height: rect.height,
        };
      }, selector);
      console.log(`FAIL: "${selector}" in DOM but not visible: ${JSON.stringify(debug)}`);
      await screenshot(page, 'fail');
      process.exit(1);
    }

    const tag = await element.evaluate((el) => el.tagName.toLowerCase());
    const text = (await element.textContent())?.trim().substring(0, 80) || '[no text]';
    console.log(`PASS: "${selector}" visible (<${tag}>: "${text}")`);
    await screenshot(page, 'pass');
    process.exit(0);

  } catch (err) {
    console.log(`FAIL: ${err.message}`);
    try { await screenshot(page, 'fail'); } catch { /* non-critical */ }
    process.exit(1);
  } finally {
    await browser.close();
  }
}

async function screenshot(page, status) {
  const path = `${SCREENSHOT_DIR}/screenshot-${status}.png`;
  try {
    mkdirSync(dirname(path), { recursive: true });
    await page.screenshot({ path, fullPage: true });
    console.log(`  Screenshot: ${path}`);
  } catch (err) {
    console.log(`  Screenshot failed: ${err.message}`);
  }
}

verify();
