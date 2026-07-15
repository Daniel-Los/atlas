import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

test('Dokploy minimal compose does not enable Overpass by default', () => {
  const compose = readFileSync(new URL('../compose.dokploy.yml', import.meta.url), 'utf8');

  assert.doesNotMatch(compose, /^\s{8}handle_path \/overpass\/\* \{/m);
  assert.doesNotMatch(compose, /^\s{2}overpass:\s*$/m);
});
