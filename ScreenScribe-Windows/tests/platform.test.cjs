'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { DEFAULTS, SettingsStore, sanitizeSettings, validShortcut } = require('../src/core/settings.cjs');
const { cropRect, panelPosition } = require('../src/capture/geometry.cjs');

test('settings accepts supported distinct shortcuts and rejects unsafe accelerator forms', () => {
  for (const value of ['Control+Shift+L', 'CommandOrControl+Shift+V', 'Alt+F8', 'Super+PrintScreen']) assert.equal(validShortcut(value), true, value);
  for (const value of ['L', 'Shift+L', 'Control+Control+L', 'Control+Alt+Shift+Super+CommandOrControl+L', 'Control+Enter', 'Control+F25', 'Control+L\n', 'Control+L;quit', '', null, 123]) assert.equal(validShortcut(value), false, String(value));
  const settings = sanitizeSettings({ captureShortcut: 'Control+Shift+L', pasteShortcut: 'Alt+Shift+S', persistImages: true, monthlyImageLimit: 20000 });
  assert.equal(settings.captureShortcut, 'Control+Shift+L'); assert.equal(settings.monthlyImageLimit, 20000); assert.equal(settings.persistImages, true);
  assert.equal(DEFAULTS.persistImages, false);
});
test('settings rejects shortcuts that refer to the same physical Windows combination', () => {
  for (const [captureShortcut, pasteShortcut] of [
    ['Control+Shift+L', 'control+shift+l'],
    ['Control+Shift+L', 'Shift+Control+L'],
    ['CommandOrControl+Shift+L', 'Control+Shift+L'],
    ['Shift+Alt+F4', 'Alt+Shift+F4'],
  ]) assert.throws(() => sanitizeSettings({ captureShortcut, pasteShortcut }), `${captureShortcut} conflicts with ${pasteShortcut}`);
});
test('settings validates incoming types, bounds and an own-property whitelist', () => {
  for (const patch of [null, [], 'settings', { provider: 'untrusted' }, { mode: 'shell' }, { persistImages: 'false' },
    { monthlyImageLimit: -1 }, { monthlyImageLimit: 1.5 }, { monthlyImageLimit: '20000' }, { monthlyImageLimit: Infinity },
    { monthlyImageLimit: 1_000_000_001 }, { visionModel: '\0model' }, { visionModel: 'x'.repeat(201) }, { visionBaseURL: 12 },
    { visionBaseURL: 'x'.repeat(2049) }, { apiKey: 'not-a-setting' }, { toString: 'untrusted' },
    JSON.parse('{"__proto__":{"polluted":true}}'), { constructor: 'untrusted' }]) assert.throws(() => sanitizeSettings(patch));
  assert.equal({}.polluted, undefined);
  assert.equal(sanitizeSettings({ monthlyImageLimit: 0 }).monthlyImageLimit, 0);
});
test('settings corruption uses defaults without implicit overwrite; explicit save recovers', () => {
  let writes = 0, saved;
  const store = new SettingsStore({ read: () => { throw new Error('private path'); }, write: (_name, value) => { writes++; saved = structuredClone(value); } });
  assert.deepEqual(store.value, DEFAULTS); assert.ok(store.error); assert.equal(store.error.includes('private path'), false); assert.equal(writes, 0);
  store.save({ monthlyImageLimit: 20000 }); assert.equal(writes, 1); assert.equal(saved.monthlyImageLimit, 20000);
});
test('invalid persisted settings do not leak partial data into defaults and failed save rolls back', () => {
  const store = new SettingsStore({ read: () => ({ provider: 'invalid', persistImages: true }), write: () => { throw new Error('disk failure'); } });
  assert.equal(store.value.provider, 'mathpix'); assert.equal(store.value.persistImages, false);
  assert.throws(() => store.save({ persistImages: true })); assert.equal(store.value.persistImages, false);
});

test('capture uses display-local coordinates on negative-origin monitors at mixed DPI', () => {
  const display = { x: -1536, y: -200, width: 1536, height: 864 };
  // A 125% monitor thumbnail: this public fixture has a known 400×200 patch.
  assert.deepEqual(cropRect({ x: 100, y: 80, width: 320, height: 160 }, display, { width: 1920, height: 1080 }), { x: 125, y: 100, width: 400, height: 200 });
  // The same DIP selection has a different size when Electron supplies a
  // smaller thumbnail; no assumed scaleFactor or primary-monitor offset.
  assert.deepEqual(cropRect({ x: 600, y: 300, width: 300, height: 180 }, display, { width: 1024, height: 576 }), { x: 400, y: 200, width: 200, height: 120 });
  assert.deepEqual(cropRect({ x: 100, y: 80, width: 320, height: 160 }, { ...display, x: 3000, y: 500 }, { width: 1920, height: 1080 }), { x: 125, y: 100, width: 400, height: 200 });
});
test('capture rounds outward and clamps a partly off-screen selection to actual pixels', () => {
  assert.deepEqual(cropRect({ x: 10.25, y: 5.5, width: 100.5, height: 20.25 }, { width: 1920, height: 1080 }, { width: 1600, height: 900 }), { x: 8, y: 4, width: 85, height: 18 });
  assert.deepEqual(cropRect({ x: -20, y: -30, width: 100, height: 80 }, { width: 100, height: 100 }, { width: 200, height: 300 }), { x: 0, y: 0, width: 160, height: 150 });
  assert.deepEqual(cropRect({ x: 95, y: 95, width: 100, height: 100 }, { width: 100, height: 100 }, { width: 200, height: 300 }), { x: 190, y: 285, width: 10, height: 15 });
});
test('capture rejects tiny, nonnumeric and wholly outside selections before cropping', () => {
  const bounds = { width: 100, height: 100 }, image = { width: 200, height: 200 };
  for (const selection of [null, { x: 0, y: 0, width: 1, height: 20 }, { x: 0, y: 0, width: -5, height: 20 },
    { x: 110, y: 10, width: 20, height: 20 }, { x: -50, y: 10, width: 20, height: 20 },
    { x: NaN, y: 0, width: 20, height: 20 }, { x: 0, y: Infinity, width: 20, height: 20 },
    { x: '0', y: 0, width: 20, height: 20 }]) assert.throws(() => cropRect(selection, bounds, image));
  assert.throws(() => cropRect({ x: 0, y: 0, width: 20, height: 20 }, bounds, { width: 0, height: 100 }));
  assert.throws(() => cropRect({ x: 0, y: 0, width: 2, height: 2 }, bounds, { width: 10, height: 10 }));
});
test('tray panel stays within negative-origin work areas and fits a small display', () => {
  const display = { workArea: { x: -1280, y: -200, width: 1280, height: 1024 } };
  const result = panelPosition({ x: -30, y: 824, width: 20, height: 20 }, display);
  assert.deepEqual(result, { width: 716, height: 524, x: -726, y: 292 });
  assert.deepEqual(panelPosition({ x: 1000, y: 1000, width: 20, height: 20 }, { workArea: { x: -400, y: -300, width: 400, height: 300 } }), { width: 400, height: 300, x: -400, y: -300 });
});
