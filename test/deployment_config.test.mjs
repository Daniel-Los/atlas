import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

test('Caddy forwards the external request scheme to Phoenix', () => {
  const caddyfile = readFileSync(new URL('../Caddyfile', import.meta.url), 'utf8');
  const dokployCompose = readFileSync(new URL('../compose.dokploy.yml', import.meta.url), 'utf8');

  assert.match(caddyfile, /header_up\s+X-Forwarded-Proto\s+https/);
  assert.match(dokployCompose, /header_up\s+X-Forwarded-Proto\s+https/);
});
