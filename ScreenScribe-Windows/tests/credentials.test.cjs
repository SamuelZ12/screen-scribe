'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { JsonFileStore } = require('../src/core/storage.cjs');
const { CredentialVault } = require('../src/core/credentials.cjs');
function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'screenscribe-vault-test-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const key = crypto.randomBytes(32);
  const adapter = {
    available: async () => true,
    encrypt: async plain => { const iv = crypto.randomBytes(12), c = crypto.createCipheriv('aes-256-gcm', key, iv); const data = Buffer.concat([c.update(plain, 'utf8'), c.final()]); return Buffer.concat([iv, c.getAuthTag(), data]); },
    decrypt: async buffer => { const d = crypto.createDecipheriv('aes-256-gcm', key, buffer.subarray(0, 12)); d.setAuthTag(buffer.subarray(12, 28)); return Buffer.concat([d.update(buffer.subarray(28)), d.final()]).toString('utf8'); }
  };
  const store = new JsonFileStore(dir); return { dir, store, adapter, vault: new CredentialVault(store, adapter) };
}
test('vault saves only encrypted bytes and whitelists credentials', async t => {
  const { dir, vault } = fixture(t); const value = { appId: 'test-only-account', apiKey: 'test-only-secret', unwanted: 'discard-me' };
  assert.equal(await vault.status('mathpix'), false);
  await vault.save('mathpix', value);
  assert.equal(await vault.status('mathpix'), true);
  assert.deepEqual(await vault.load('mathpix'), { appId: value.appId, apiKey: value.apiKey });
  const stored = fs.readFileSync(path.join(dir, 'credentials.json'), 'utf8');
  for (const secret of [value.appId, value.apiKey, 'discard-me']) assert.equal(stored.includes(secret), false);
  await vault.remove('mathpix'); assert.equal(await vault.load('mathpix'), null);
});
test('vision encrypted secrets are isolated by normalized endpoint', async t => {
  const { dir, vault } = fixture(t);
  await vault.save('vision', { apiKey: 'key-A' }, 'https://EXAMPLE.org/v1/');
  assert.deepEqual(await vault.load('vision', 'https://example.org/v1'), { apiKey: 'key-A' });
  assert.equal(await vault.load('vision', 'https://example.org/other'), null);
  await vault.save('vision', { apiKey: 'key-B' }, 'https://another.example/v1');
  await vault.remove('vision', 'https://example.org/v1');
  assert.deepEqual(await vault.load('vision', 'https://another.example/v1'), { apiKey: 'key-B' });
  const stored = fs.readFileSync(path.join(dir, 'credentials.json'), 'utf8');
  assert.equal(stored.includes('example'), false);
  for (const url of ['http://example.org', 'https://user:pass@example.org', 'https://example.org/?key=x', 'https://example.org/#x']) await assert.rejects(vault.save('vision', { apiKey: 'fake' }, url));
});
test('vault unavailable encryption never falls back to plaintext or changes saved data', async t => {
  const { vault, dir, store, adapter } = fixture(t);
  await vault.save('mathpix', { appId: 'test', apiKey: 'fake-key' });
  const before = fs.readFileSync(path.join(dir, 'credentials.json'), 'utf8');
  adapter.available = async () => false;
  await assert.rejects(vault.load('mathpix'));
  await assert.rejects(vault.save('mathpix', { appId: 'test', apiKey: 'another-fake' }));
  assert.equal(fs.readFileSync(path.join(dir, 'credentials.json'), 'utf8'), before);
  const plainVault = new CredentialVault(store, { available: async () => true, encrypt: async p => Buffer.from(p) });
  await assert.rejects(plainVault.save('mathpix', { appId: 'test', apiKey: 'another-fake' }));
  await vault.remove('mathpix'); assert.equal(await vault.status('mathpix'), false);
});
test('vault corrupt ciphertext and plaintext file remain untouched with safe errors', async t => {
  const { vault, store, dir } = fixture(t);
  store.write('credentials.json', { version: 1, entries: { mathpix: Buffer.from('not-an-encrypted-record').toString('base64') } });
  const before = fs.readFileSync(path.join(dir, 'credentials.json'), 'utf8');
  await assert.rejects(vault.load('mathpix'), e => !e.message.includes('not-an-encrypted-record') && !e.message.includes(dir));
  assert.equal(fs.readFileSync(path.join(dir, 'credentials.json'), 'utf8'), before);
  store.write('credentials.json', { appId: 'test', apiKey: 'fake-secret' });
  await assert.rejects(vault.save('mathpix', { appId: 'new', apiKey: 'fake-new' }));
  assert.equal(store.read('credentials.json').apiKey, 'fake-secret');
});
test('vault rejects invalid provider and credential contents', async t => {
  const { vault } = fixture(t);
  for (const value of [{ appId: '', apiKey: 'x' }, { appId: 'a\nb', apiKey: 'x' }, { appId: 'a', apiKey: 'x\n' }, {}, null]) await assert.rejects(vault.save('mathpix', value));
  await assert.rejects(vault.save('untrusted', { apiKey: 'fake' }));
});
