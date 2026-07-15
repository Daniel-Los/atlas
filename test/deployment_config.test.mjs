import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

test('Valhalla has a safe worker cap and nofile limit by default', () => {
  const compose = readFileSync(new URL('../compose.yml', import.meta.url), 'utf8');

  assert.match(compose, /server_threads:\s+\$\{VALHALLA_THREADS:-4\}/);
  assert.match(compose, /ulimits:\n\s+nofile:\n\s+soft:\s+1048576\n\s+hard:\s+1048576/);
});
