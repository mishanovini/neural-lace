#!/usr/bin/env tsx
/**
 * audit-consistency.ts — Generic code-consistency audit for web projects.
 *
 * Scans a codebase for common pattern violations:
 * - Raw string formatting that should use shared helpers
 * - Unapproved color classes (orange, yellow) not in the Tailwind palette
 * - HTML entity arrows (&larr;) that should use icon libraries
 * - <h1> in content pages (should be <h2>)
 * - text-xl on page titles (should be text-2xl)
 * - Outline-only buttons (violates "filled button" rule)
 * - Missing loading.tsx for server-component pages with async fetches
 * - Inline category color objects that should use a shared module
 *
 * Exit code: 0 if clean, 1 if P0/P1 violations found.
 *
 * Copy to your project's scripts/ directory and run:
 *   npx tsx scripts/audit-consistency.ts
 *
 * Add to package.json:
 *   "audit:consistency": "npx tsx scripts/audit-consistency.ts"
 *
 * Configuration (optional): create `.audit-consistency.json` in project root:
 *   {
 *     "srcDir": "src",
 *     "ignorePaths": ["node_modules", ".next", "test-results"],
 *     "approvedColors": ["blue", "green", "red", "amber", "purple", "gray"],
 *     "formatHelpers": {
 *       "snake_case_replace": "formatLabel from @/lib/format"
 *     }
 *   }
 *
 * Part of the global testing framework at ~/.claude/scripts/
 */

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';

interface AuditConfig {
  srcDir: string;
  ignorePaths: string[];
  approvedColors: string[];
  standardTitleSize: string;
}

const DEFAULT_CONFIG: AuditConfig = {
  srcDir: 'src',
  ignorePaths: ['node_modules', '.next', 'test-results', 'playwright-report', '.git', 'dist', 'build'],
  approvedColors: ['blue', 'green', 'red', 'amber', 'purple', 'gray'],
  standardTitleSize: 'text-2xl',
};

function loadConfig(root: string): AuditConfig {
  const configPath = join(root, '.audit-consistency.json');
  if (existsSync(configPath)) {
    try {
      const custom = JSON.parse(readFileSync(configPath, 'utf-8'));
      return { ...DEFAULT_CONFIG, ...custom };
    } catch (err) {
      console.error(`Warning: could not parse ${configPath}:`, err);
    }
  }
  return DEFAULT_CONFIG;
}

const ROOT = process.cwd();
const CONFIG = loadConfig(ROOT);
const SRC_DIR = join(ROOT, CONFIG.srcDir);

interface Finding {
  severity: 'P0' | 'P1' | 'P2';
  category: string;
  file: string;
  line: number;
  message: string;
  snippet: string;
}

const findings: Finding[] = [];

function walkFiles(dir: string, exts: string[]): string[] {
  const results: string[] = [];
  if (!existsSync(dir)) return results;
  const entries = readdirSync(dir);
  for (const entry of entries) {
    const full = join(dir, entry);
    const stat = statSync(full);
    if (stat.isDirectory()) {
      if (CONFIG.ignorePaths.includes(entry)) continue;
      results.push(...walkFiles(full, exts));
    } else if (exts.some((ext) => entry.endsWith(ext))) {
      results.push(full);
    }
  }
  return results;
}

function addFinding(
  severity: Finding['severity'],
  category: string,
  file: string,
  line: number,
  message: string,
  snippet: string,
): void {
  findings.push({
    severity,
    category,
    file: relative(ROOT, file),
    line,
    message,
    snippet: snippet.trim().slice(0, 120),
  });
}

// ─── Check 1: Raw .replace(/_/g, ' ') instead of a formatter helper ─────────
function checkRawStringFormatting(lines: string[], file: string): void {
  if (file.includes('/trigger/') || file.includes('/lib/ai/') || file.includes('audit-consistency')) return;
  if (!file.includes('/components/') && !file.includes('/app/') && !file.includes('/pages/')) return;

  lines.forEach((line, idx) => {
    if (line.trim().startsWith('//') || line.trim().startsWith('*')) return;
    if (line.includes('.replace(/_/g, \' \')') || line.includes('.replace(/_/g, " ")')) {
      addFinding(
        'P1',
        'String formatting',
        file,
        idx + 1,
        'Raw .replace(/_/g, " ") — use a shared formatLabel() helper instead',
        line,
      );
    }
  });
}

// ─── Check 2: Unapproved Tailwind color classes ─────────────────────────────
function checkUnapprovedColors(lines: string[], file: string): void {
  if (!file.includes('/components/') && !file.includes('/app/') && !file.includes('/pages/')) return;

  // Build a regex from colors NOT in the approved list
  const allColors = ['orange', 'yellow', 'pink', 'indigo', 'violet', 'fuchsia', 'rose', 'sky', 'cyan', 'teal', 'emerald', 'lime'];
  const unapproved = allColors.filter((c) => !CONFIG.approvedColors.includes(c));
  if (unapproved.length === 0) return;

  const pattern = new RegExp(`\\b((?:text|bg|border)-(?:${unapproved.join('|')})-\\d{2,3}(?:\\/\\d{1,3})?)\\b`);

  lines.forEach((line, idx) => {
    if (line.trim().startsWith('//') || line.trim().startsWith('*')) return;
    const match = line.match(pattern);
    if (match) {
      addFinding(
        'P2',
        'Color palette',
        file,
        idx + 1,
        `"${match[1]}" is not in the approved palette (${CONFIG.approvedColors.join(', ')})`,
        line,
      );
    }
  });
}

// ─── Check 3: HTML entity arrows instead of icon library ────────────────────
function checkHtmlEntityArrows(lines: string[], file: string): void {
  if (!file.includes('/components/') && !file.includes('/app/') && !file.includes('/pages/')) return;

  lines.forEach((line, idx) => {
    if (line.trim().startsWith('//') || line.trim().startsWith('*')) return;
    if (/&l?arr;|&r?arr;|&uarr;|&darr;/i.test(line)) {
      addFinding(
        'P2',
        'Navigation patterns',
        file,
        idx + 1,
        'HTML entity arrow — use an icon library (lucide-react ArrowLeft/ArrowRight) for consistent styling',
        line,
      );
    }
  });
}

// ─── Check 4: <h1> in content pages (should be <h2>, layout has h1) ────────
function checkH1InPages(lines: string[], file: string): void {
  if (!file.endsWith('page.tsx') && !file.endsWith('page.ts') && !file.includes('-client.tsx') && !file.includes('-detail')) return;
  // Exempt: layout files, logo components, and any page NOT inside the main dashboard layout.
  // Pages outside (dashboard) group (auth, onboarding, book, set-password, login) don't have
  // a layout h1, so their own h1 is correct.
  // Normalize path separators for cross-platform matching.
  const normalized = file.replace(/\\/g, '/');
  const exempt = /\/(sidebar|logo|layout|login|\(auth\)|\(onboarding\)|onboarding|book|set-password|auth)/i;
  if (exempt.test(normalized)) return;

  lines.forEach((line, idx) => {
    if (line.trim().startsWith('//')) return;
    if (/<h1[\s>]/.test(line)) {
      addFinding(
        'P2',
        'Typography',
        file,
        idx + 1,
        '<h1> in page — use <h2> to match heading hierarchy (root layout has the h1)',
        line,
      );
    }
  });
}

// ─── Check 5: Page title size consistency ───────────────────────────────────
function checkPageTitleSize(lines: string[], file: string): void {
  if (!file.endsWith('page.tsx') && !file.includes('-client.tsx')) return;
  // Exempt pages outside the main dashboard layout (multi-step flows often use different sizes)
  const normalized = file.replace(/\\/g, '/');
  const exempt = /\/(login|\(auth\)|\(onboarding\)|onboarding|book|set-password|auth)/i;
  if (exempt.test(normalized)) return;

  lines.forEach((line, idx) => {
    if (line.trim().startsWith('//')) return;
    // Match <h2> with any text-* class that isn't the standard
    const heading = line.match(/<h2[^>]*className="([^"]*)"/);
    if (!heading) return;
    const classes = heading[1];
    if (!classes.includes('font-bold')) return; // only flag bold headings (page titles)
    // Check for text-xl, text-3xl, text-4xl (wrong sizes for page titles)
    const wrongSize = classes.match(/\btext-(xl|3xl|4xl|base|sm|lg)\b/);
    if (wrongSize && !classes.includes(CONFIG.standardTitleSize)) {
      addFinding(
        'P2',
        'Typography',
        file,
        idx + 1,
        `Page title uses ${wrongSize[0]} — should be ${CONFIG.standardTitleSize}`,
        line,
      );
    }
  });
}

// ─── Check 6: Outline-only buttons ──────────────────────────────────────────
function checkOutlineButtons(lines: string[], file: string): void {
  if (!file.includes('/components/') && !file.includes('/app/') && !file.includes('/pages/')) return;

  lines.forEach((line, idx) => {
    if (line.trim().startsWith('//')) return;
    // Skip non-button lines quickly
    if (!line.includes('className=')) return;
    if (!line.includes('button') && !line.includes('Button')) return;

    const hasBorderColor = /border-(?:blue|purple|green|red|amber)-\d{3}/.test(line);
    const hasTextColor = /text-(?:blue|purple|green|red|amber)-\d{3}/.test(line);
    const hasBgFill = /bg-(?:blue|purple|green|red|amber|gray)-(?:100|200|500|600|700|800|900)/.test(line);

    if (hasBorderColor && hasTextColor && !hasBgFill) {
      // Skip badges, pills, status indicators
      if (/rounded-full|badge|pill|chip/i.test(line)) return;
      addFinding(
        'P2',
        'Button style',
        file,
        idx + 1,
        'Possible outline-only button — action buttons should have a filled background for visibility in dark mode',
        line,
      );
    }
  });
}

// ─── Check 7: Missing loading.tsx for async server components ───────────────
function checkMissingLoadingFiles(): void {
  const appDir = join(SRC_DIR, 'app');
  if (!existsSync(appDir)) return;

  function walkRoutes(dir: string): void {
    const entries = readdirSync(dir);
    for (const entry of entries) {
      if (CONFIG.ignorePaths.includes(entry)) continue;
      const full = join(dir, entry);
      const stat = statSync(full);
      if (stat.isDirectory()) {
        walkRoutes(full);
      } else if (entry === 'page.tsx' || entry === 'page.ts') {
        const pageContent = readFileSync(full, 'utf-8');
        // Only server components (no 'use client')
        if (/^\s*['"]use client['"]/.test(pageContent)) continue;
        // Only pages that do async work
        if (!/\bawait\s|\basync\s+function/.test(pageContent)) continue;
        const loadingFile = join(dir, 'loading.tsx');
        if (!existsSync(loadingFile)) {
          addFinding(
            'P1',
            'Loading states',
            full,
            1,
            'Server component with async work is missing a loading.tsx file in the same directory',
            'missing loading.tsx',
          );
        }
      }
    }
  }

  walkRoutes(appDir);
}

// ─── Check 8: Inline fallback chains that should use a formatter helper ────
function checkFallbackChains(lines: string[], file: string): void {
  if (!file.includes('/components/') && !file.includes('/app/')) return;

  lines.forEach((line, idx) => {
    if (line.trim().startsWith('//')) return;
    // Look for: stateLabels[x] ?? formatLabel(x) — a manual fallback chain
    if (/\w+Labels?\[[^\]]+\]\s*\?\?\s*formatLabel/.test(line)) {
      addFinding(
        'P2',
        'String formatting',
        file,
        idx + 1,
        'Manual fallback chain — create a dedicated helper (e.g., formatStateName) that encapsulates this logic',
        line,
      );
    }
  });
}

// ─── Check 9: Documentation staleness ───────────────────────────────────────
//
// Scans long-lived user-facing docs (README, docs/*.md) for:
// - Missing "Last verified" header (90-day freshness signal)
// - Stale "Last verified" dates (>90 days ago)
// - Parallel backlog tracking files (violates single-source-of-truth rule)
function checkDocStaleness(): void {
  const docsDir = join(ROOT, 'docs');
  const readmePath = join(ROOT, 'README.md');

  const filesToCheck: string[] = [];
  if (existsSync(readmePath)) filesToCheck.push(readmePath);
  if (existsSync(docsDir)) {
    const excluded = new Set(['decisions', 'reviews', 'sessions', 'plans']);
    for (const entry of readdirSync(docsDir)) {
      const full = join(docsDir, entry);
      const stat = statSync(full);
      if (stat.isDirectory()) {
        if (excluded.has(entry)) continue;
      } else if (entry.endsWith('.md')) {
        filesToCheck.push(full);
      }
    }
  }

  // Detect parallel backlog trackers (single-source-of-truth rule)
  const parallelTrackers = ['feature-gaps.md', 'remaining-work.md', 'todo.md', 'future-enhancements.md', 'roadmap.md', 'wishlist.md'];
  for (const tracker of parallelTrackers) {
    const trackerPath = join(docsDir, tracker);
    if (existsSync(trackerPath)) {
      addFinding(
        'P1',
        'Doc staleness',
        trackerPath,
        1,
        `Parallel backlog tracker — migrate items to docs/backlog.md and delete this file (single-source-of-truth rule)`,
        `parallel tracker: ${tracker}`,
      );
    }
  }

  const now = Date.now();
  const STALE_MS = 90 * 24 * 60 * 60 * 1000;
  for (const file of filesToCheck) {
    const content = readFileSync(file, 'utf-8');
    const lines = content.split('\n').slice(0, 10);
    const lastVerifiedMatch = lines.join('\n').match(/Last verified:[^\d]*(\d{4}-\d{2}-\d{2})/);
    const lastUpdatedMatch = lines.join('\n').match(/Last updated:[^\d]*(\d{4}-\d{2}-\d{2})/);

    if (!lastVerifiedMatch && !lastUpdatedMatch) {
      addFinding(
        'P2',
        'Doc staleness',
        file,
        1,
        'No "Last verified:" or "Last updated:" date header — add one to enable staleness tracking',
        'missing header',
      );
      continue;
    }

    const dateStr = (lastVerifiedMatch?.[1] ?? lastUpdatedMatch?.[1]) as string;
    const docDate = new Date(dateStr).getTime();
    if (isNaN(docDate)) continue;
    const age = now - docDate;
    if (age > STALE_MS) {
      const daysOld = Math.floor(age / (24 * 60 * 60 * 1000));
      addFinding(
        'P2',
        'Doc staleness',
        file,
        1,
        `Doc is ${daysOld} days old (>90 day threshold). Review against current state and update the date header.`,
        `last date: ${dateStr}`,
      );
    }
  }
}

// ─── Run all checks ─────────────────────────────────────────────────────────
const allFiles = walkFiles(SRC_DIR, ['.tsx', '.ts']);

const lineChecks = [
  checkRawStringFormatting,
  checkUnapprovedColors,
  checkHtmlEntityArrows,
  checkH1InPages,
  checkPageTitleSize,
  checkOutlineButtons,
  checkFallbackChains,
];

for (const file of allFiles) {
  const content = readFileSync(file, 'utf-8');
  const lines = content.split('\n');
  for (const check of lineChecks) {
    check(lines, file);
  }
}

checkMissingLoadingFiles();
checkDocStaleness();

// ─── Report ─────────────────────────────────────────────────────────────────
const byCategory = new Map<string, Finding[]>();
for (const f of findings) {
  if (!byCategory.has(f.category)) byCategory.set(f.category, []);
  byCategory.get(f.category)!.push(f);
}

const COLOR = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
};

console.log(`\n${COLOR.bold}${COLOR.cyan}Consistency Audit${COLOR.reset}`);
console.log(`${COLOR.dim}Scanned ${allFiles.length} files in ${CONFIG.srcDir}/${COLOR.reset}\n`);

if (findings.length === 0) {
  console.log(`${COLOR.bold}\u2713 No violations found.${COLOR.reset}\n`);
  process.exit(0);
}

const p0 = findings.filter((f) => f.severity === 'P0').length;
const p1 = findings.filter((f) => f.severity === 'P1').length;
const p2 = findings.filter((f) => f.severity === 'P2').length;

const sortedCategories = Array.from(byCategory.entries()).sort((a, b) => {
  const severityWeight = (items: Finding[]) =>
    items.reduce((sum, f) => sum + (f.severity === 'P0' ? 100 : f.severity === 'P1' ? 10 : 1), 0);
  return severityWeight(b[1]) - severityWeight(a[1]);
});

for (const [category, items] of sortedCategories) {
  console.log(`${COLOR.bold}${category}${COLOR.reset} ${COLOR.dim}(${items.length})${COLOR.reset}`);
  for (const item of items.slice(0, 10)) {
    const sevColor = item.severity === 'P0' ? COLOR.red : item.severity === 'P1' ? COLOR.yellow : COLOR.blue;
    console.log(`  ${sevColor}${item.severity}${COLOR.reset} ${item.file}:${item.line} \u2014 ${item.message}`);
  }
  if (items.length > 10) {
    console.log(`  ${COLOR.dim}... and ${items.length - 10} more${COLOR.reset}`);
  }
  console.log();
}

console.log(`${COLOR.bold}Summary:${COLOR.reset} ${COLOR.red}${p0} P0${COLOR.reset}, ${COLOR.yellow}${p1} P1${COLOR.reset}, ${COLOR.blue}${p2} P2${COLOR.reset} (${findings.length} total)\n`);

process.exit(p0 + p1 > 0 ? 1 : 0);
