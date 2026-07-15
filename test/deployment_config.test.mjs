import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

test('Overpass diff updates are opt-in by default', () => {
  const compose = readFileSync(new URL('../compose.yml', import.meta.url), 'utf8');

  assert.match(compose, /OVERPASS_DIFF_URL:\s+\$\{OVERPASS_DIFF_URL:-\}/);
});
