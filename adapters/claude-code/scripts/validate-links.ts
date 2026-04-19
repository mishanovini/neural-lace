/**
 * validate-links.ts — Generic dead link validator for web projects.
 *
 * Crawls all href values in source files and verifies they resolve to
 * valid routes. Works with Next.js (App Router), Remix, and any
 * framework that uses page.tsx/page.ts files for routing.
 *
 * Copy to your project's tests/ directory and run:
 *   npx tsx tests/validate-links.ts              # Validate against file system
 *   npx tsx tests/validate-links.ts --live        # Validate against running server
 *   npx tsx tests/validate-links.ts --live --base=https://your-app.com
 *
 * Add to package.json:
 *   "test:links": "npx tsx tests/validate-links.ts"
 *   "test:links:live": "npx tsx tests/validate-links.ts --live"
 *
 * Part of the global testing framework at ~/.claude/scripts/
 */

import { readFileSync, readdirSync, statSync } from 'fs';
import { resolve, join, relative, extname } from 'path';

const ROOT = resolve(__dirname, '..');
const SRC = join(ROOT, 'src');

function walkDir(dir: string, exts: string[]): string[] {
  const results: string[] = [];
  try {
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry);
      try {
        const stat = statSync(full);
        if (stat.isDirectory() && !entry.startsWith('.') && entry !== 'node_modules') {
          results.push(...walkDir(full, exts));
        } else if (stat.isFile() && exts.includes(extname(entry))) {
          results.push(full);
        }
      } catch { /* permission errors */ }
    }
  } catch { /* directory doesn't exist */ }
  return results;
}

interface ExtractedLink {
  href: string;
  file: string;
  line: number;
}

function extractLinks(): ExtractedLink[] {
  const files = walkDir(SRC, ['.tsx', '.ts', '.jsx', '.js']);
  const links: ExtractedLink[] = [];
  const hrefRegex = /href=["']([^"']+)["']/g;

  for (const filePath of files) {
    const content = readFileSync(filePath, 'utf8');
    const lines = content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      let match;
      hrefRegex.lastIndex = 0;
      while ((match = hrefRegex.exec(lines[i])) !== null) {
        const href = match[1];
        if (href.startsWith('http') || href.startsWith('mailto:') || href === '#') continue;
        if (href.includes('${') || href.startsWith('/api/')) continue;
        if (href.includes('[') || href.includes(']')) continue;

        links.push({
          href,
          file: relative(ROOT, filePath).replace(/\\/g, '/'),
          line: i + 1,
        });
      }
    }
  }

  return links;
}

function discoverRoutes(): Set<string> {
  const routes = new Set<string>();
  const appDir = join(SRC, 'app');
  const pageFiles = walkDir(appDir, ['.tsx', '.ts', '.jsx', '.js']).filter(
    (f) => /page\.(tsx?|jsx?)$/.test(f)
  );

  for (const pageFile of pageFiles) {
    let route = relative(appDir, pageFile)
      .replace(/\\/g, '/')
      .replace(/\/page\.(tsx?|jsx?)$/, '')
      .replace(/\([^)]+\)\//g, '')
      .replace(/\([^)]+\)$/, '');

    if (route === '') route = '/';
    if (!route.startsWith('/')) route = '/' + route;
    routes.add(route);
    if (route.endsWith('/') && route !== '/') routes.add(route.slice(0, -1));
  }

  return routes;
}

function routeMatches(href: string, routes: Set<string>): boolean {
  const cleanHref = href.split('#')[0].split('?')[0];
  if (routes.has(cleanHref)) return true;

  for (const route of routes) {
    if (route.includes('[')) {
      const pattern = route.replace(/\[[^\]]+\]/g, '[^/]+');
      if (new RegExp(`^${pattern}$`).test(cleanHref)) return true;
    }
  }
  return false;
}

interface BrokenLink extends ExtractedLink {
  status?: number;
  reason: string;
}

async function validateLive(links: ExtractedLink[], baseUrl: string): Promise<BrokenLink[]> {
  const broken: BrokenLink[] = [];
  const checked = new Map<string, number>();

  for (const link of links) {
    const cleanHref = link.href.split('#')[0].split('?')[0];
    if (checked.has(cleanHref)) {
      const status = checked.get(cleanHref)!;
      if (status >= 400) broken.push({ ...link, status, reason: `HTTP ${status}` });
      continue;
    }

    try {
      const url = new URL(cleanHref, baseUrl);
      const res = await fetch(url.toString(), {
        method: 'HEAD',
        redirect: 'manual',
        signal: AbortSignal.timeout(5000),
      });
      checked.set(cleanHref, res.status);
      if (res.status >= 400) broken.push({ ...link, status: res.status, reason: `HTTP ${res.status}` });
    } catch (err) {
      checked.set(cleanHref, 0);
      broken.push({ ...link, status: 0, reason: err instanceof Error ? err.message : 'Network error' });
    }
  }
  return broken;
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const isLive = args.includes('--live');
  const baseArg = args.find((a) => a.startsWith('--base='));
  const baseUrl = baseArg ? baseArg.split('=')[1] : 'http://localhost:3000';

  console.log('🔗 Dead Link Validator\n');

  const links = extractLinks();
  const uniqueHrefs = new Set(links.map((l) => l.href.split('#')[0].split('?')[0]));
  console.log(`Found ${links.length} internal links (${uniqueHrefs.size} unique).\n`);

  let broken: BrokenLink[] = [];

  if (isLive) {
    console.log(`Validating against: ${baseUrl}\n`);
    broken = await validateLive(links, baseUrl);
  } else {
    const routes = discoverRoutes();
    console.log(`Discovered ${routes.size} routes.\n`);
    for (const link of links) {
      if (!routeMatches(link.href, routes)) {
        broken.push({ ...link, reason: 'No matching page file found' });
      }
    }
  }

  if (broken.length === 0) {
    console.log('✅ All links are valid!\n');
    process.exit(0);
  } else {
    console.log(`❌ Found ${broken.length} broken link(s):\n`);
    for (const b of broken) {
      console.log(`  ${b.file}:${b.line}`);
      console.log(`    href="${b.href}"`);
      console.log(`    Reason: ${b.reason}\n`);
    }
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
