'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { JsonFileStore } = require('../src/core/storage.cjs');
function fixture(t) { const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'screenscribe-storage-test-')); t.after(() => fs.rmSync(dir, { recursive: true, force: true })); return { dir, store: new JsonFileStore(path.join(dir, 'data')) }; }

test('storage atomically writes JSON and creates private directory/files', t => {
  const { dir, store } = fixture(t), fallback = { enabled: true };
  const fresh = store.read('settings.json', fallback); fresh.enabled = false;
  assert.equal(fallback.enabled, true);
  store.write('settings.json', { enabled: true, words: '中文' });
  assert.deepEqual(store.read('settings.json'), { enabled: true, words: '中文' });
  store.write('settings.json', { enabled: false });
  assert.deepEqual(store.read('settings.json'), { enabled: false });
  assert.deepEqual(fs.readdirSync(path.join(dir, 'data')), ['settings.json']);
  if (process.platform !== 'win32') {
    assert.equal(fs.statSync(path.join(dir, 'data')).mode & 0o777, 0o700);
    assert.equal(fs.statSync(path.join(dir, 'data/settings.json')).mode & 0o777, 0o600);
  }
});
test('storage rejects traversal, absolute paths and reserved Windows filenames', t => {
  const { store } = fixture(t);
  for (const name of ['../outside', '/tmp/file', '..', '.', 'file/path', 'file\\path', 'CON', 'COM1.json', 'trailing.', 'a:b', 'name\0']) {
    assert.throws(() => store.write(name, {}), { code: 'STORE_NAME_INVALID' });
    assert.throws(() => store.read(name, null), { code: 'STORE_NAME_INVALID' });
  }
});
test('storage preserves corrupt contents and never exposes its path in errors', t => {
  const { dir, store } = fixture(t); fs.mkdirSync(path.join(dir, 'data'));
  const file = path.join(dir, 'data/bad.json'); fs.writeFileSync(file, '{broken');
  assert.throws(() => store.read('bad.json', {}), error => error.code === 'STORE_CORRUPT' && !error.message.includes(dir));
  assert.equal(fs.readFileSync(file, 'utf8'), '{broken');
  const circular = {}; circular.self = circular;
  assert.throws(() => store.write('bad.json', circular), { code: 'STORE_WRITE_FAILED' });
  assert.equal(fs.readFileSync(file, 'utf8'), '{broken');
});
test('storage refuses file and directory symbolic links', { skip: process.platform === 'win32' }, t => {
  const { dir, store } = fixture(t); const outside = path.join(dir, 'outside.json'); fs.writeFileSync(outside, '{"safe":true}');
  fs.mkdirSync(path.join(dir, 'data')); fs.symlinkSync(outside, path.join(dir, 'data/link.json'));
  assert.throws(() => store.read('link.json', {}), { code: 'STORE_READ_FAILED' });
  assert.throws(() => store.write('link.json', {}), { code: 'STORE_WRITE_FAILED' });
  assert.equal(fs.readFileSync(outside, 'utf8'), '{"safe":true}');
  fs.symlinkSync(path.join(dir, 'data'), path.join(dir, 'alias'));
  const alias = new JsonFileStore(path.join(dir, 'alias'));
  assert.throws(() => alias.read('settings.json', {}), { code: 'STORE_READ_FAILED' });
  assert.throws(() => alias.write('settings.json', {}), { code: 'STORE_WRITE_FAILED' });
});
test('storage failure is explicit and leaves no partial replacement', t => {
  const { dir } = fixture(t); const notDirectory = path.join(dir, 'block'); fs.writeFileSync(notDirectory, 'x');
  const store = new JsonFileStore(notDirectory);
  assert.throws(() => store.write('settings.json', {}), { code: 'STORE_WRITE_FAILED' });
  assert.equal(fs.readFileSync(notDirectory, 'utf8'), 'x');
});
