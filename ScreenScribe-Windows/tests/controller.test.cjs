'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { Controller } = require('../src/core/controller.cjs');
const { JsonFileStore } = require('../src/core/storage.cjs');
const { HistoryStore } = require('../src/core/history.cjs');
const { CreditStore } = require('../src/core/credit.cjs');
const services = require('../src/services/providers.cjs');

// All IDs, keys and API responses are synthetic. Only temporary test-directory
// JSON is read/written; no network, OS vault, screenshots or GUI is used.
const APP_A = 'integration-fake-app-a';
const APP_B = 'integration-fake-app-b';
const KEY_A = 'integration-fake-key-a';
const KEY_B = 'integration-fake-key-b';
const BASE_A = 'https://vision.example.test/v1';
const BASE_B = 'https://second.example.test/v1';
const NOW = new Date();
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jH6kAAAAASUVORK5CYII=', 'base64');
const PUBLIC_FORMULA_PNG = fs.readFileSync(path.join(__dirname, '../assets/test-equation.png'));
const dataURL = (png) => `data:image/png;base64,${png.toString('base64')}`;
const clone = (value) => value == null ? null : structuredClone(value);
function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

function fakeVault() {
  const scope = (provider, base) => provider === 'mathpix' ? provider : `vision:${services.normalizeVisionBase(base)}`;
  const records = new Map([
    ['mathpix', { appId: APP_A, apiKey: KEY_A }],
    [`vision:${BASE_A}`, { apiKey: 'integration-fake-vision-key-a' }],
    [`vision:${BASE_B}`, { apiKey: 'integration-fake-vision-key-b' }],
    ['vision:https://api.openai.com/v1', { apiKey: 'integration-fake-openai-key' }]
  ]);
  const delays = [];
  const loads = [];
  return {
    records, loads,
    holdNext(provider, base) {
      const started = deferred(), release = deferred();
      delays.push({ key: scope(provider, base), started, release });
      return { started: started.promise, release: () => release.resolve() };
    },
    async load(provider, base) {
      const key = scope(provider, base);
      const value = clone(records.get(key));
      loads.push({ provider, base });
      const index = delays.findIndex((item) => item.key === key);
      if (index >= 0) {
        const [item] = delays.splice(index, 1);
        item.started.resolve();
        await item.release.promise;
      }
      return value;
    },
    async status(provider, base) { return records.has(scope(provider, base)); },
    async save(provider, value, base) { records.set(scope(provider, base), clone(value)); return true; },
    async remove(provider, base) { records.delete(scope(provider, base)); return true; }
  };
}

async function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'screenscribe-controller-test-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const storage = new JsonFileStore(dir);
  const history = new HistoryStore(storage);
  const credit = new CreditStore(storage);
  const vault = fakeVault();
  const calls = { mathpix: [], vision: [], usage: [], clipboard: [], cancelCapture: 0 };
  const outputs = [];
  const h = { dir, storage, history, credit, vault, calls, outputs, selectedPNG: PNG };
  const providers = {
    ...services,
    recognizeMathpix: (options) => services.recognizeMathpix({ ...options, transport: async (request) => {
      calls.mathpix.push(request);
      const next = outputs.length ? outputs.shift() : { latex_styled: 'x^2+1', confidence: 1 };
      if (next instanceof Error) throw next;
      return typeof next === 'function' ? next(request) : next;
    } }),
    recognizeVision: (options) => services.recognizeVision({ ...options, transport: async (request) => {
      calls.vision.push(request);
      return { choices: [{ finish_reason: 'stop', message: { content: 'y=2x' } }] };
    } }),
    fetchMathpixUsage: (options) => services.fetchMathpixUsage({ ...options, now: NOW, transport: async (request) => {
      calls.usage.push(request);
      return { ocr_usage: [{ app_id: options.appId, usage_type: 'image', count: 31 + calls.mathpix.length }] };
    } })
  };
  const io = {
    platform: 'win32', testPNG: PUBLIC_FORMULA_PNG,
    capture: async () => h.selectedPNG, importImage: async () => h.selectedPNG, pasteImage: async () => h.selectedPNG,
    cancelCapture: () => { calls.cancelCapture++; }, registerShortcuts: () => null,
    copyText: (text) => calls.clipboard.push({ kind: 'text', text }),
    copyPNG: (png) => calls.clipboard.push({ kind: 'png', png: Buffer.from(png) }),
    hide() {}, quit() {}, setPinned() {}, openDataFolder() {}, openHelp() {}
  };
  const controller = new Controller({ storage, vault, history, credit, io, providers });
  Object.assign(h, { controller, providers, io });
  await controller.initialize();
  if (controller.usageRequest) await controller.usageRequest.promise;
  calls.usage.length = 0; // Startup's one read-only refresh is separately complete.
  controller.currentPNG = PNG;
  return h;
}

test('rapid double recognition is locked before asynchronous credential loading and sends once', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  h.controller.credentials.clear();
  const held = h.vault.holdNext('mathpix');
  const first = h.controller.action('recognize');
  await held.started;
  assert.equal(h.controller.state().busy, true);
  const second = await h.controller.action('recognize');
  assert.equal(second.ok, false);
  assert.match(second.error, /正在进行/);
  assert.equal(h.calls.mathpix.length, 0);
  held.release();
  assert.equal((await first).ok, true);
  assert.equal(h.calls.mathpix.length, 1);
  assert.equal(h.history.list().length, 1);
  assert.equal(h.credit.record.localAttempts, '1');
  assert.equal(h.credit.snapshot().completionRemainder, 1);
  assert.equal(h.controller.state().busy, false);
});

test('cancel during credential await sends nothing, consumes no quota and preserves selected Original', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  h.controller.credentials.clear();
  const held = h.vault.holdNext('mathpix');
  const recognition = h.controller.action('recognize');
  await held.started;
  assert.equal(h.controller.state().result.imageDataUrl, dataURL(PNG));
  assert.equal((await h.controller.action('cancel')).ok, true);
  held.release();
  await recognition;
  assert.equal(h.calls.mathpix.length, 0);
  assert.equal(h.credit.record.localAttempts, '0');
  assert.equal(h.credit.snapshot().completionRemainder, 0);
  assert.equal(h.history.list().length, 0);
  assert.equal(h.controller.state().result.imageDataUrl, dataURL(PNG));
  assert.equal(h.controller.state().busy, false);
});

test('changing the vision endpoint during credential await cancels the old request and isolates the new key', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  await h.controller.action('update-settings', { provider: 'vision', visionBaseURL: BASE_A, visionModel: 'fake-vision-model' });
  const held = h.vault.holdNext('vision', BASE_A);
  const recognition = h.controller.action('recognize');
  await held.started;
  assert.equal((await h.controller.action('update-settings', { visionBaseURL: `${BASE_B}/` })).ok, true);
  held.release();
  await recognition;
  assert.equal(h.calls.vision.length, 0);
  assert.equal(h.controller.state().settings.visionBaseURL, BASE_B);
  assert.equal(h.controller.state().credentialStatus.vision, true);
  assert.equal(h.controller.credentials.has(`vision:${BASE_A}`), false);
  assert.equal((await h.controller.action('recognize')).ok, true);
  assert.equal(h.calls.vision.length, 1);
  assert.equal(h.calls.vision[0].url, `${BASE_B}/chat/completions`);
  assert.equal(h.calls.vision[0].headers.Authorization, 'Bearer integration-fake-vision-key-b');
  const publicState = JSON.stringify(h.controller.state());
  assert.ok(!publicState.includes('integration-fake-vision-key-a'));
  assert.ok(!publicState.includes('integration-fake-vision-key-b'));
});

test('rapid usage refreshes coalesce even before credentials resolve', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  h.controller.credentials.clear();
  const held = h.vault.holdNext('mathpix');
  const first = h.controller.action('refresh-usage');
  await held.started;
  const task = h.controller.usageRequest;
  const second = h.controller.action('refresh-usage');
  assert.equal(h.controller.usageRequest, task);
  assert.equal(h.calls.usage.length, 0);
  held.release();
  const completed = await Promise.all([first, second]);
  assert.deepEqual(completed.map((entry) => entry.ok), [true, true]);
  assert.equal(h.calls.usage.length, 1);
  assert.equal(h.controller.usageRequest, null);
  assert.equal(h.controller.state().quota.monthlyUsed, 31);
});

test('usage returning after account replacement cannot refill the new account even if provider ignores abort', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  const started = deferred(), oldResponse = deferred();
  const normalFetch = h.providers.fetchMathpixUsage;
  h.providers.fetchMathpixUsage = async (options) => {
    if (options.appId === APP_A) { started.resolve(); return oldResponse.promise; }
    return normalFetch(options);
  };
  const old = h.controller.action('refresh-usage');
  await started.promise;
  assert.equal((await h.controller.action('save-credentials', { provider: 'mathpix', appId: APP_B, apiKey: KEY_B })).ok, true);
  assert.equal(h.controller.state().quota.monthlyUsed, 31);
  const oldPeriod = h.credit.record.usage;
  oldResponse.resolve({ ...oldPeriod, imageCount: 999_999 });
  await old;
  assert.equal(h.controller.state().quota.monthlyUsed, 31);
  assert.equal(h.credit.record.usage.imageCount, 31);
  assert.equal(h.controller.usageRequest, null);
  assert.equal(h.calls.usage.length, 1);
  const state = JSON.stringify(h.controller.state());
  for (const sensitive of [APP_A, APP_B, KEY_A, KEY_B]) assert.ok(!state.includes(sensitive));
});

test('usage cancelled while credentials load never sends or adopts an old account result', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  h.controller.credentials.clear();
  const held = h.vault.holdNext('mathpix');
  const old = h.controller.action('refresh-usage');
  await held.started;
  await h.controller.action('update-settings', { monthlyImageLimit: 20_000 });
  held.release();
  await old;
  assert.equal(h.calls.usage.length, 0);
  assert.equal(h.controller.state().quota.monthlyUsed, 31);
  assert.equal(h.controller.state().quota.monthlyRemaining, 19_969);
  assert.equal(h.controller.usageRequest, null);
});

test('an old credential load cannot repopulate the cache after replacement', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  h.controller.credentials.clear();
  const held = h.vault.holdNext('mathpix');
  const staleRead = h.controller.getCredentials('mathpix');
  await held.started;
  assert.equal((await h.controller.action('save-credentials', { provider: 'mathpix', appId: APP_B, apiKey: KEY_B })).ok, true);
  held.release();
  assert.equal(await staleRead, null);
  assert.deepEqual(await h.controller.getCredentials('mathpix'), { appId: APP_B, apiKey: KEY_B });
  assert.equal(h.controller.credentials.get('mathpix').appId, APP_B);
});

test('an old vision credential load cannot resurrect a deleted endpoint key', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  await h.controller.action('update-settings', { provider: 'vision', visionBaseURL: BASE_A });
  const held = h.vault.holdNext('vision', BASE_A);
  const staleRead = h.controller.getCredentials('vision', BASE_A);
  await held.started;
  assert.equal((await h.controller.action('delete-credentials', { provider: 'vision', baseURL: BASE_A })).ok, true);
  held.release();
  assert.equal(await staleRead, null);
  assert.equal(await h.controller.getCredentials('vision', BASE_A), null);
  assert.equal(h.controller.state().credentialStatus.vision, false);
});

test('without Billing every actual send is persisted and the fifth completed request queries official usage', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  // Two OCR failures still count as attempts/completions; no billing snapshot is
  // required for the five-request cadence, including across store reconstruction.
  h.outputs.push({ error: 'synthetic failure', error_info: { id: 'image_no_content' } }, { latex_styled: 'x' },
    { error: 'synthetic failure', error_info: { id: 'math_confidence' } }, { latex_styled: 'y' }, { latex_styled: 'z' });
  for (let index = 1; index <= 5; index++) {
    const response = await h.controller.action('recognize');
    assert.equal(response.ok, ![1, 3].includes(index));
    assert.equal(h.calls.mathpix.length, index);
    assert.equal(h.credit.record.localAttempts, String(index));
    assert.equal(h.controller.state().quota.remaining, null);
    assert.equal(h.controller.state().quota.completionRemainder, index % 5);
    assert.equal(h.calls.usage.length, index === 5 ? 1 : 0);
    const restored = new CreditStore(h.storage); restored.selectAccount(APP_A);
    assert.equal(restored.snapshot().completionRemainder, index % 5);
    assert.equal(restored.record.localAttempts, String(index));
  }
  assert.equal(h.controller.state().quota.monthlyUsed, 36);
  assert.equal(h.controller.state().quota.nextRefreshIn, 5);
  assert.equal(h.history.list().length, 3);
});

test('a quota write failure stops before the image request and cannot produce a completion', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  const write = h.storage.write.bind(h.storage);
  h.storage.write = (name, value) => {
    if (name.startsWith('credit.')) throw Error('synthetic disk failure');
    return write(name, value);
  };
  const result = await h.controller.action('recognize');
  assert.equal(result.ok, false);
  assert.equal(h.calls.mathpix.length, 0);
  assert.equal(h.credit.record.completionRemainder, 0);
  assert.equal(h.controller.state().result.imageDataUrl, dataURL(PNG));
});

test('history write failure preserves a successful result for copying and later manual saving', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  const write = h.storage.write.bind(h.storage);
  let failHistory = true;
  h.storage.write = (name, value) => {
    if (failHistory && name === 'history.json') throw Error('synthetic history failure with secret-like body');
    return write(name, value);
  };
  const recognized = await h.controller.action('recognize');
  assert.equal(recognized.ok, true);
  assert.equal(h.controller.state().result.code, 'x^2+1');
  assert.equal(h.controller.state().result.imageDataUrl, dataURL(PNG));
  assert.match(h.controller.state().notice, /仅保留在当前面板/);
  assert.ok(!h.controller.state().error.includes('secret-like'));
  assert.deepEqual(h.history.list(), []);
  assert.equal((await h.controller.action('copy-source', { format: 'inline' })).ok, true);
  assert.deepEqual(h.calls.clipboard.at(-1), { kind: 'text', text: '$x^2+1$' });
  failHistory = false;
  assert.equal((await h.controller.action('save-source', { code: 'x^2+1=0' })).ok, true);
  assert.equal(new HistoryStore(h.storage).list()[0].code, 'x^2+1=0');
  assert.equal(h.controller.state().result.code, 'x^2+1=0');
  assert.equal(h.calls.mathpix.length, 1);
});

test('a failed new recognition shows its own Original and can retry the exact selected PNG', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  assert.equal((await h.controller.action('recognize')).ok, true);
  const oldID = h.controller.state().result.id;
  h.selectedPNG = PUBLIC_FORMULA_PNG;
  h.outputs.push({ error_info: { id: 'image_no_content' } });
  const failed = await h.controller.action('capture');
  assert.equal(failed.ok, false);
  const pending = h.controller.state().result;
  assert.notEqual(pending.id, oldID);
  assert.equal(pending.code, '');
  assert.equal(pending.imageDataUrl, dataURL(PUBLIC_FORMULA_PNG));
  assert.deepEqual(h.controller.currentPNG, PUBLIC_FORMULA_PNG);
  assert.equal(h.history.list().length, 1);
  assert.equal((await h.controller.action('copy-png')).ok, true);
  assert.deepEqual(h.calls.clipboard.at(-1).png, PUBLIC_FORMULA_PNG);
  assert.equal((await h.controller.action('recognize')).ok, true);
  assert.equal(JSON.parse(h.calls.mathpix[1].body).src, dataURL(PUBLIC_FORMULA_PNG));
  assert.equal(JSON.parse(h.calls.mathpix[2].body).src, dataURL(PUBLIC_FORMULA_PNG));
  assert.equal(h.history.list().length, 2);
  assert.equal(h.controller.state().result.code, 'x^2+1');
  assert.equal(h.credit.record.localAttempts, '3');
});

test('manual source saving promotes a failed pending result to history without another API request', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  h.outputs.push({ error_info: { id: 'math_confidence' } });
  assert.equal((await h.controller.action('recognize')).ok, false);
  const pendingID = h.controller.state().result.id;
  const code = String.raw`\text{ a  b }+\mathrm{d}x+\,y`;
  assert.equal((await h.controller.action('save-source', { code })).ok, true);
  assert.equal(h.controller.state().result.id, pendingID);
  assert.equal(h.controller.state().result.code, code);
  assert.equal(h.controller.state().result.imageDataUrl, dataURL(PNG));
  const saved = new HistoryStore(h.storage).list();
  assert.equal(saved.length, 1);
  assert.equal(saved[0].id, pendingID);
  assert.equal(saved[0].code, code);
  assert.equal(saved[0].imageDataUrl, undefined);
  assert.equal(h.calls.mathpix.length, 1);
  assert.equal(h.credit.record.localAttempts, '1');
});

test('state/history/disk never include fake credentials and unsupported inherited actions are rejected', { timeout: 3000 }, async (t) => {
  const h = await fixture(t);
  await h.controller.action('recognize');
  const state = JSON.stringify(h.controller.state());
  const files = fs.readdirSync(h.dir).filter((name) => name.endsWith('.json')).map((name) => fs.readFileSync(path.join(h.dir, name), 'utf8')).join('\n');
  for (const sensitive of [APP_A, APP_B, KEY_A, KEY_B]) {
    assert.ok(!state.includes(sensitive));
    assert.ok(!files.includes(sensitive));
  }
  assert.equal((await h.controller.action('toString')).ok, false);
  assert.equal((await h.controller.action('constructor')).ok, false);
  assert.equal((await h.controller.action('recognize', null)).ok, false);
});
