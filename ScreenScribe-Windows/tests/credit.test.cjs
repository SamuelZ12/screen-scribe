'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { JsonFileStore } = require('../src/core/storage.cjs');
const { CreditStore } = require('../src/core/credit.cjs');
const NOW = new Date('2026-10-24T08:00:00.000Z');
const A = 'test-account-A', B = 'test-account-B';
function fixture(t) { const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'screenscribe-credit-test-')); t.after(() => fs.rmSync(dir, { recursive: true, force: true })); const store = new JsonFileStore(dir); return { dir, store, credit: new CreditStore(store) }; }
function billing(credit, creditUSD = '100.00', pendingUSD = '0.00', imagePriceUSD = '0.002') { credit.saveBilling({ creditUSD, pendingUSD, imagePriceUSD, observedAt: NOW }); }
function usage(credit, imageCount, month = 10) { return credit.reconcile({ imageCount, periodStart: `2026-${String(month).padStart(2, '0')}-01T00:00:00.000Z`, periodEnd: `${month === 12 ? 2027 : 2026}-${String(month === 12 ? 1 : month + 1).padStart(2, '0')}-01T00:00:00.000Z`, fetchedAt: `2026-${String(month).padStart(2, '0')}-24T08:00:00.000Z` }); }
function snapshot(credit) { return credit.snapshot(20000, NOW); }
function name(id) { return `credit.${createHash('sha256').update(id).digest('hex')}.json`; }

test('credit has no invented balance, exact pending cent margin and one debit per attempt', t => {
  const { credit } = fixture(t);
  assert.equal(snapshot(credit).remaining, null); assert.throws(() => billing(credit));
  credit.selectAccount(A); billing(credit, '10.00', '0.03');
  assert.equal(snapshot(credit).remaining, 4980);
  for (let i = 1; i <= 7; i++) { credit.recordAttempt(A); assert.equal(snapshot(credit).remaining, 4980 - i); }
  assert.equal(credit.recordAttempt(B), false); assert.equal(snapshot(credit).remaining, 4973);
  assert.equal(credit.recordAttempt(A + '\n'), false);
  assert.match(snapshot(credit).detail, /非实时余额/);
  assert.equal(snapshot(credit).detail.includes(A), false);
});
test('credit rejects malformed decimal precision without replacing last valid billing', t => {
  const { credit } = fixture(t); credit.selectAccount(A); billing(credit, '10.00', '0.03');
  for (const creditUSD of ['10.001', '-1', '1e5', 'NaN', '.05', '1.', ' 10.00', 10, '1000000.01']) assert.throws(() => billing(credit, creditUSD));
  for (const price of ['0', '-0.01', '0.0000001', '1000.000001', 'Infinity']) assert.throws(() => billing(credit, '1.00', '0.00', price));
  assert.equal(snapshot(credit).remaining, 4980);
  billing(credit, '0.01', '0.05'); assert.equal(snapshot(credit).remaining, 0);
  billing(credit, '1.00', '0.00', '0.000001'); assert.equal(snapshot(credit).remaining, 990000);
});
test('cadence persists without Billing, survives restart, account switch, clear and new snapshot', t => {
  const { credit, store, dir } = fixture(t); credit.selectAccount(A);
  for (let i = 1; i <= 3; i++) { assert.equal(credit.recordAttempt(A), true); assert.equal(credit.recordCompletion(A), false); }
  assert.equal(snapshot(credit).completionRemainder, 3); assert.equal(snapshot(credit).remaining, null);
  const restarted = new CreditStore(store); restarted.selectAccount(A);
  assert.equal(snapshot(restarted).nextRefreshIn, 2);
  restarted.selectAccount(B); assert.equal(snapshot(restarted).completionRemainder, 0);
  restarted.recordAttempt(B); restarted.recordCompletion(B);
  restarted.selectAccount(A); billing(restarted); assert.equal(snapshot(restarted).completionRemainder, 3);
  restarted.recordAttempt(A); assert.equal(restarted.recordCompletion(A), false);
  restarted.clearBilling(); assert.equal(snapshot(restarted).completionRemainder, 4);
  restarted.recordAttempt(A); assert.equal(restarted.recordCompletion(A), true);
  restarted.recordAttempt(A); assert.equal(restarted.recordCompletion(A), false);
  restarted.selectAccount(B); assert.equal(snapshot(restarted).completionRemainder, 1);
  restarted.selectAccount(null); assert.equal(snapshot(restarted).remaining, null); assert.equal(restarted.recordAttempt(A), false);
  restarted.selectAccount(A); assert.equal(snapshot(restarted).completionRemainder, 1);
  const raw = fs.readdirSync(dir).map(file => file + fs.readFileSync(path.join(dir, file), 'utf8')).join('');
  assert.equal(raw.includes(A), false); assert.equal(raw.includes(B), false); assert.equal(raw.includes('apiKey'), false);
});
test('usage high-water avoids both double-charge and increase, including external use followed by local use', t => {
  const { credit, store } = fixture(t); credit.selectAccount(A); billing(credit); usage(credit, 0);
  const initial = snapshot(credit).remaining;
  for (let i = 0; i < 5; i++) credit.recordAttempt(A);
  assert.equal(snapshot(credit).remaining, initial - 5);
  usage(credit, 3); assert.equal(snapshot(credit).remaining, initial - 5);
  usage(credit, 8); assert.equal(snapshot(credit).remaining, initial - 8);
  credit.recordAttempt(A); assert.equal(snapshot(credit).remaining, initial - 9);
  usage(credit, 9); usage(credit, 9); usage(credit, 5);
  assert.equal(snapshot(credit).remaining, initial - 9);
  assert.equal(snapshot(credit).monthlyUsed, 9); assert.equal(snapshot(credit).monthlyRemaining, 19991);
  const restarted = new CreditStore(store); restarted.selectAccount(A); usage(restarted, 9);
  assert.equal(snapshot(restarted).remaining, initial - 9);
});
test('known initial image cost rounds up to cents only once and preserves exact subsequent debits', t => {
  const { credit, store } = fixture(t); credit.selectAccount(A); billing(credit, '10.00', '0.04');
  credit.recordAttempt(A); credit.recordAttempt(A); assert.equal(snapshot(credit).remaining, 4973);
  usage(credit, 35); assert.equal(snapshot(credit).remaining, 4963);
  usage(credit, 37); assert.equal(snapshot(credit).remaining, 4963);
  credit.recordAttempt(A); assert.equal(snapshot(credit).remaining, 4962);
  usage(credit, 38); assert.equal(snapshot(credit).remaining, 4962);
  usage(credit, 45); assert.equal(snapshot(credit).remaining, 4955);
  assert.match(snapshot(credit).detail, /额外预留 10 次/);
  const restarted = new CreditStore(store); restarted.selectAccount(A); usage(restarted, 45);
  assert.equal(snapshot(restarted).remaining, 4955);
});
test('cross-month usage carries debit and hides stale total until a new observed Billing snapshot', t => {
  const { credit, store } = fixture(t); credit.selectAccount(A); billing(credit); usage(credit, 0);
  for (let i = 0; i < 5; i++) credit.recordAttempt(A);
  usage(credit, 9); usage(credit, 2, 11);
  const november = new Date('2026-11-24T09:00:00.000Z');
  let q = credit.snapshot(20000, november);
  assert.equal(q.stale, true); assert.equal(q.remaining, null); assert.equal(q.monthlyUsed, 2);
  assert.equal(store.read(name(A)).accounted, '11');
  usage(credit, 4, 11); usage(credit, 4, 11); assert.equal(store.read(name(A)).accounted, '13');
  assert.equal(usage(credit, 500, 10), false);
  credit.recordAttempt(A); usage(credit, 5, 11); assert.equal(store.read(name(A)).accounted, '14');
  credit.saveBilling({ creditUSD: '90.00', pendingUSD: '0.04', imagePriceUSD: '0.002', observedAt: november });
  usage(credit, 5, 11); q = credit.snapshot(20000, november);
  assert.equal(q.stale, false); assert.equal(q.remaining, 44975);
  assert.equal(credit.snapshot(20000, new Date('2026-12-01T00:01:00Z')).remaining, null);
  assert.equal(credit.snapshot(20000, new Date('2026-12-01T00:01:00Z')).monthlyUsed, null);
});
test('server periods, unsafe counts and corrupted persisted counters cannot fabricate allowance', t => {
  const { credit, store } = fixture(t); credit.selectAccount(A); billing(credit); usage(credit, 0);
  for (const imageCount of [-1, 1.2, Infinity, Number.MAX_SAFE_INTEGER + 1]) assert.throws(() => usage(credit, imageCount));
  assert.throws(() => credit.reconcile({ imageCount: 1, periodStart: '2026-10-01T00:00:01Z', periodEnd: '2026-11-01T00:00:00Z', fetchedAt: NOW.toISOString() }));
  const data = store.read(name(A)); data.accounted = '-1'; store.write(name(A), data);
  const corrupt = new CreditStore(store); assert.throws(() => corrupt.selectAccount(A));
  assert.equal(snapshot(corrupt).remaining, null); assert.equal(snapshot(corrupt).stale, true);
  assert.throws(() => corrupt.recordAttempt(A)); assert.equal(store.read(name(A)).accounted, '-1');
  billing(corrupt); assert.equal(snapshot(corrupt).remaining, 49995);
});
test('storage failure blocks stale positive allowance and rejects unsafe transmission accounting', t => {
  const { credit, store } = fixture(t); credit.selectAccount(A); billing(credit);
  store.write = () => { throw new Error('private path or secret'); };
  assert.throws(() => credit.recordAttempt(A), error => error.safeMessage && !error.safeMessage.includes('private path'));
  assert.equal(snapshot(credit).remaining, null); assert.equal(snapshot(credit).stale, true);
});
test('microdollar arithmetic and one-per-image invariants across decimal price grid', () => {
  // Disk persistence is covered above. This exhaustive arithmetic grid uses an
  // isolated in-memory store to avoid thousands of unnecessary disk flushes.
  const data = new Map();
  const credit = new CreditStore({ read: (key, fallback) => structuredClone(data.get(key) ?? fallback), write: (key, value) => data.set(key, structuredClone(value)) });
  credit.selectAccount(A);
  let combinations = 0;
  for (let cents = 0; cents <= 30; cents++) {
    for (let pending = 0; pending <= 8; pending++) {
      for (const price of [1n, 3n, 999n, 1000n, 1500n, 2000n, 3000n, 17000n]) {
        const c = (cents / 100).toFixed(2), p = (pending / 100).toFixed(2), fraction = price.toString().padStart(6, '0');
        billing(credit, c, p, `0.${fraction}`);
        let expected = (BigInt(cents) * 10000n - BigInt(pending) * 10000n - 10000n) / price;
        if (expected < 0n) expected = 0n;
        assert.equal(snapshot(credit).remaining, Number(expected));
        credit.recordAttempt(A); assert.equal(snapshot(credit).remaining, Math.max(0, Number(expected) - 1));
        combinations++;
      }
    }
  }
  assert.equal(combinations, 2232);
});
test('corrupted high-water floors cannot resurrect an overstated balance on restart', t => {
  const { credit, store } = fixture(t); credit.selectAccount(A); billing(credit); usage(credit, 0); usage(credit, 9);
  const data = store.read(name(A)); data.accounted = '0'; store.write(name(A), data);
  const corrupted = new CreditStore(store); assert.throws(() => corrupted.selectAccount(A));
  assert.equal(snapshot(corrupted).remaining, null);
});
