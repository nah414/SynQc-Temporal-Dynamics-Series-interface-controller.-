#!/usr/bin/env node
/**
 * Best-effort Playwright installer with mirror + tarball support.
 * - If PLAYWRIGHT_TARBALL is set and exists, installs from that file (no registry needed).
 * - Otherwise, installs from PLAYWRIGHT_REGISTRY or defaults to https://registry.npmjs.org.
 * This script is designed to be safe for CI and local runs and to avoid interfering with live use.
 */

const { existsSync } = require('fs');
const { spawnSync } = require('child_process');
const path = require('path');

const pkg = '@playwright/test@1.45.0';
const defaultTarball = path.join(__dirname, 'vendor', 'playwright-test-1.45.0.tgz');
const tarball = process.env.PLAYWRIGHT_TARBALL || (existsSync(defaultTarball) ? defaultTarball : null);
const registry = process.env.PLAYWRIGHT_REGISTRY || 'https://registry.npmjs.org';

function alreadyInstalled() {
  try {
    require.resolve('@playwright/test');
    return true;
  } catch (_) {
    return false;
  }
}

if (alreadyInstalled()) {
  console.log('[playwright:fetch] @playwright/test already installed; skipping fetch.');
  process.exit(0);
}

let installArg = pkg;
if (tarball) {
  const resolved = path.resolve(tarball);
  if (existsSync(resolved)) {
    installArg = resolved;
    console.log(`[playwright:fetch] Installing from tarball: ${resolved}`);
  } else {
    console.warn(`[playwright:fetch] PLAYWRIGHT_TARBALL set but file not found: ${resolved}. Falling back to registry.`);
  }
} else {
  console.log(`[playwright:fetch] Installing from registry: ${registry}`);
}

const result = spawnSync('npm', ['install', installArg, '--no-save', '--registry', registry], {
  stdio: 'inherit',
  env: {
    ...process.env,
  },
});

if (result.status !== 0) {
  console.warn('[playwright:fetch] Install did not succeed. You may need to provide PLAYWRIGHT_TARBALL or registry access.');
  process.exit(result.status || 1);
}

console.log('[playwright:fetch] @playwright/test available.');
