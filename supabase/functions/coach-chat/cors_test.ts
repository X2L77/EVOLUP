import assert from 'node:assert/strict';
import { corsHeadersFor, isAllowedOrigin, originPolicyFrom } from './cors.ts';

const local = originPolicyFrom(undefined);

Deno.test('loopback origins are allowed on any port, without configuration', () => {
  for (
    const origin of [
      'http://localhost',
      'http://localhost:5000',
      'http://localhost:8080',
      'http://localhost:65535',
      'https://localhost:5001',
      'http://127.0.0.1:5000',
      'http://127.0.0.1:49152',
      'http://127.0.0.2:3000',
      'http://[::1]:5000',
    ]
  ) {
    assert.ok(isAllowedOrigin(origin, local), origin);
  }
});

Deno.test('private LAN addresses are allowed only with an explicit port', () => {
  for (
    const origin of [
      'http://192.168.1.42:8080',
      'http://192.168.0.10:5000',
      'http://10.0.0.5:5000',
      'http://172.16.0.3:3000',
      'http://172.31.255.254:8080',
    ]
  ) {
    assert.ok(isAllowedOrigin(origin, local), origin);
  }
  for (
    const origin of [
      'http://192.168.1.1', // router or device page
      'https://10.0.0.1',
      'http://172.15.0.3:3000', // public
      'http://172.32.0.3:3000', // public
      'http://100.64.0.1:5000', // carrier-grade NAT
      'http://169.254.1.1:5000', // link-local
      'http://8.8.8.8:5000',
      'http://[fd00::1]:5000',
    ]
  ) {
    assert.equal(isAllowedOrigin(origin, local), false, origin);
  }
});

Deno.test('look-alike, malformed and non-canonical origins are refused', () => {
  for (
    const origin of [
      'null',
      '',
      '*',
      'localhost:5000',
      'http://localhost.evil.example:5000',
      'http://evil.example?localhost:5000',
      'http://localhost:5000@evil.example',
      'http://localhost:5000/',
      'http://LOCALHOST:5000',
      'http://0x7f.0.0.1:5000',
      'http://2130706433:5000',
      'http://192.168.1.42.nip.io:8080',
      'ws://localhost:5000',
      'file://localhost',
      'chrome-extension://abcdef',
    ]
  ) {
    assert.equal(isAllowedOrigin(origin, local), false, JSON.stringify(origin));
  }
});

Deno.test('production origins are the exact https origins configured', () => {
  const policy = originPolicyFrom(
    ' https://app.evolup.example/ ,https://EVOLUP.example:8443,, ',
  );
  assert.deepEqual([...policy.production].sort(), [
    'https://app.evolup.example',
    'https://evolup.example:8443',
  ]);
  assert.deepEqual(policy.ignored, []);
  assert.ok(isAllowedOrigin('https://app.evolup.example', policy));
  assert.ok(isAllowedOrigin('https://evolup.example:8443', policy));
  for (
    const origin of [
      'http://app.evolup.example',
      'https://evolup.example',
      'https://other.evolup.example',
      'https://app.evolup.example.evil.example',
      'https://app.evolup.example:444',
    ]
  ) {
    assert.equal(isAllowedOrigin(origin, policy), false, origin);
  }
});

Deno.test('wildcards, paths and plain http are ignored in the configuration', () => {
  const policy = originPolicyFrom(
    '*, https://*.evolup.example, http://app.evolup.example, ' +
      'https://app.evolup.example/path, https://user@app.evolup.example, ' +
      'not an origin, https://ok.evolup.example',
  );
  assert.deepEqual([...policy.production], ['https://ok.evolup.example']);
  assert.equal(policy.ignored.length, 6);
  assert.equal(isAllowedOrigin('https://evil.example', policy), false);
});

Deno.test('COACH_LOCAL_ORIGINS=off disables local development origins', () => {
  for (const value of ['off', ' OFF ']) {
    const policy = originPolicyFrom('https://app.evolup.example', value);
    assert.equal(policy.local, false);
    assert.equal(isAllowedOrigin('http://localhost:5000', policy), false);
    assert.equal(isAllowedOrigin('http://192.168.1.42:8080', policy), false);
    assert.ok(isAllowedOrigin('https://app.evolup.example', policy));
  }
  assert.ok(originPolicyFrom(undefined, '').local);
  assert.ok(originPolicyFrom(undefined, 'on').local);
});

Deno.test('CORS headers: none without Origin, null when refused', () => {
  assert.deepEqual(corsHeadersFor(null, local), {});
  assert.equal(corsHeadersFor('https://evil.example', local), null);
  const headers = corsHeadersFor('http://localhost:7357', local);
  assert.equal(
    headers?.['Access-Control-Allow-Origin'],
    'http://localhost:7357',
  );
  assert.equal(headers?.['Access-Control-Allow-Methods'], 'POST, OPTIONS');
  assert.equal(
    headers?.['Access-Control-Allow-Headers'],
    'authorization, x-client-info, apikey, content-type, x-region',
  );
  assert.equal(headers?.Vary, 'Origin');
});
