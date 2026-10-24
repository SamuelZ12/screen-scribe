'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { JsonFileStore } = require('../src/core/storage.cjs');
const { HistoryStore } = require('../src/core/history.cjs');
function fixture(t) { const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'screenscribe-history-test-')); t.after(() => fs.rmSync(dir, { recursive: true, force: true })); const store = new JsonFileStore(dir); return { dir, store, history: new HistoryStore(store) }; }
function entry(id, imageDataUrl) { return { id, createdAt: '2026-10-24T00:00:00.000Z', mode: 'equation', provider: 'mathpix', model: 'v3/text', code: 'x^2', structure: '', warnings: [], confidence: 0.95, imageDataUrl }; }
const tinyPNG = 'data:image/png;base64,' + Buffer.from('89504e470d0a1a0a00000000', 'hex').toString('base64');
test('history whitelists fields, defaults to no persisted image, caps newest 50', t => {
  const { history, store } = fixture(t);
  history.add({ ...entry('one', tinyPNG), apiKey: 'fake', appId: 'fake-id', secret: 'drop' });
  assert.equal(history.list()[0].imageDataUrl, undefined);
  assert.equal(history.list()[0].apiKey, undefined);
  for (let i = 0; i < 55; i++) history.add(entry(`item-${i}`));
  const list = history.list(); assert.equal(list.length, 50); assert.equal(list[0].id, 'item-54'); assert.equal(list[49].id, 'item-5');
  list[0].code = 'mutation'; assert.equal(history.list()[0].code, 'x^2');
  assert.equal(new HistoryStore(store).list()[0].code, 'x^2');
});
test('history supports explicit image persistence, source edits, delete and image removal', t => {
  const { history, store } = fixture(t);
  history.add(entry('one', tinyPNG), { persistImages: true }); history.add(entry('two', tinyPNG), { persistImages: true });
  assert.equal(new HistoryStore(store).list()[0].imageDataUrl, tinyPNG);
  history.update('one', 'y=3'); assert.equal(history.list()[1].code, 'y=3');
  history.remove('two'); assert.equal(history.list().length, 1);
  history.removeImages(); assert.equal(history.list()[0].imageDataUrl, undefined);
  history.clear(); assert.deepEqual(new HistoryStore(store).list(), []);
});
test('history enforces a serialized 25 MB budget without unlimited single entries', t => {
  const { history } = fixture(t); const png = Buffer.alloc(9_400_000); Buffer.from('89504e470d0a1a0a', 'hex').copy(png);
  const image = 'data:image/png;base64,' + png.toString('base64');
  history.add(entry('one', image), { persistImages: true }); history.add(entry('two', image), { persistImages: true });
  assert.equal(history.list().length, 1); assert.equal(history.list()[0].id, 'two');
  assert.ok(Buffer.byteLength(JSON.stringify(history.list())) <= 25_000_000);
  assert.throws(() => history.add({ ...entry('big-code'), code: 'x'.repeat(1_000_001) }));
  assert.throws(() => history.add(entry('bad-image', 'data:image/png;base64,abcd'), { persistImages: true }));
});
test('history preserves corrupted file and blocks implicit writes until explicit clear', t => {
  const { dir, store } = fixture(t); const file = path.join(dir, 'history.json'); fs.writeFileSync(file, '{not json');
  const history = new HistoryStore(store);
  assert.deepEqual(history.list(), []); assert.ok(history.error);
  assert.throws(() => history.add(entry('one'))); assert.throws(() => history.removeImages());
  assert.equal(fs.readFileSync(file, 'utf8'), '{not json');
  history.clear(); history.add(entry('recovered')); assert.equal(new HistoryStore(store).list()[0].id, 'recovered');
});
test('history rejects malformed confidence and duplicate persisted IDs, and rolls back write failures', t => {
  const { store, history } = fixture(t); history.add(entry('one'));
  for (const confidence of [-0.1, 1.1, Infinity, '0.5']) assert.throws(() => history.add({ ...entry('bad'), confidence }));
  const write = store.write; store.write = () => { throw new Error('secret OS path'); };
  assert.throws(() => history.update('one', 'different'), e => !e.message.includes('secret OS path'));
  assert.equal(history.list()[0].code, 'x^2'); store.write = write;
  store.write('history.json', [entry('duplicate'), entry('duplicate')]);
  const corrupt = new HistoryStore(store); assert.ok(corrupt.error); assert.throws(() => corrupt.add(entry('three')));
});
