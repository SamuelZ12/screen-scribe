'use strict';

const { createHash } = require('node:crypto');
const CENT = 10_000n;
const DOLLAR = 1_000_000n;
const MAX_COUNT = BigInt(Number.MAX_SAFE_INTEGER);
function fail() { const error = new Error('额度记录无效或无法保存。请检查存储权限并更新账单快照。'); error.safeMessage = error.message; return error; }
function hashAccount(appId) {
  if (typeof appId !== 'string' || !appId.trim() || appId.length > 512 || /[\x00-\x1f\x7f]/.test(appId)) return null;
  return createHash('sha256').update(appId.trim()).digest('hex');
}
function micros(input, digits, maximum) {
  if (typeof input !== 'string' || input.length > 24 || !/^\d+(?:\.\d+)?$/.test(input)) throw fail();
  const [whole, fraction = ''] = input.split('.');
  if (fraction.length > digits) throw fail();
  const value = BigInt(whole) * DOLLAR + BigInt(fraction.padEnd(6, '0'));
  if (value > maximum) throw fail();
  return value;
}
function count(input) {
  if (typeof input !== 'string' || !/^(0|[1-9]\d{0,15})$/.test(input) || BigInt(input) > MAX_COUNT) throw fail();
  return BigInt(input);
}
function iso(input) {
  if (typeof input !== 'string' && !(input instanceof Date)) throw fail();
  const date = new Date(input);
  if (!Number.isFinite(date.getTime())) throw fail();
  return date.toISOString();
}
function month(input) {
  const date = new Date(input);
  if (!Number.isFinite(date.getTime())) throw fail();
  date.setUTCDate(1); date.setUTCHours(0, 0, 0, 0);
  return date.toISOString();
}
function period(start, end) {
  const periodStart = iso(start), periodEnd = iso(end);
  const next = new Date(periodStart); next.setUTCMonth(next.getUTCMonth() + 1);
  if (month(periodStart) !== periodStart || next.toISOString() !== periodEnd) throw fail();
  return { periodStart, periodEnd };
}
function empty() {
  return { version: 1, billing: null, localAttempts: '0', accounted: '0', completionRemainder: 0,
    overflowed: false, needsBillingUpdate: false, usage: null, baseline: null };
}
function validate(record) {
  if (!record || record.version !== 1 || typeof record.overflowed !== 'boolean' || typeof record.needsBillingUpdate !== 'boolean' ||
      !Number.isInteger(record.completionRemainder) || record.completionRemainder < 0 || record.completionRemainder > 4) throw fail();
  const result = empty();
  result.localAttempts = count(record.localAttempts).toString(); result.accounted = count(record.accounted).toString();
  if (BigInt(result.accounted) < BigInt(result.localAttempts)) throw fail();
  result.completionRemainder = record.completionRemainder; result.overflowed = record.overflowed; result.needsBillingUpdate = record.needsBillingUpdate;
  if (record.billing !== null) {
    const b = record.billing;
    if (!b || typeof b.creditMicros !== 'string' || typeof b.pendingMicros !== 'string' || typeof b.priceMicros !== 'string') throw fail();
    const credit = count(b.creditMicros), pending = count(b.pendingMicros), price = count(b.priceMicros);
    if (credit > 1_000_000n * DOLLAR || pending > 1_000_000n * DOLLAR || price <= 0n || price > 1000n * DOLLAR || credit % CENT !== 0n || pending % CENT !== 0n) throw fail();
    result.billing = { creditMicros: credit.toString(), pendingMicros: pending.toString(), priceMicros: price.toString(), observedAt: iso(b.observedAt) };
  }
  if (record.usage !== null) {
    const u = record.usage;
    if (!u || !Number.isSafeInteger(u.imageCount) || u.imageCount < 0) throw fail();
    result.usage = { imageCount: u.imageCount, ...period(u.periodStart, u.periodEnd), fetchedAt: iso(u.fetchedAt) };
  }
  if (record.baseline !== null) {
    const b = record.baseline;
    if (!result.billing || !result.usage || !b || month(b.periodStart) !== iso(b.periodStart)) throw fail();
    const base = count(b.baseCount), high = count(b.highWater), prior = count(b.priorPeriods), precision = count(b.precisionDebits);
    const serverFloor = prior + high - base + precision;
    const localFloor = BigInt(result.localAttempts) + precision;
    if (high < base || high !== BigInt(result.usage.imageCount) || iso(b.periodStart) !== result.usage.periodStart ||
        BigInt(result.accounted) < (serverFloor > MAX_COUNT ? MAX_COUNT : serverFloor) ||
        BigInt(result.accounted) < (localFloor > MAX_COUNT ? MAX_COUNT : localFloor)) throw fail();
    result.baseline = { periodStart: iso(b.periodStart), baseCount: base.toString(), highWater: high.toString(), priorPeriods: prior.toString(), precisionDebits: precision.toString() };
  }
  return result;
}
function cap(value, record) {
  if (value > MAX_COUNT) { record.overflowed = true; return MAX_COUNT; }
  return value;
}
function ceilDivide(value, divisor) { return (value + divisor - 1n) / divisor; }
function money(value) {
  const fraction = (value % DOLLAR).toString().padStart(6, '0').replace(/0+$/, '');
  return `${value / DOLLAR}${fraction ? '.' + fraction : ''}`;
}

class CreditStore {
  constructor(store) { this.store = store; this.account = null; this.record = empty(); this.broken = false; }

  selectAccount(appId) {
    const selected = hashAccount(appId);
    if (selected === this.account) return selected !== null;
    this.account = selected; this.record = empty(); this.broken = false;
    if (!selected) return false;
    try { this.record = validate(this.store.read(`credit.${selected}.json`, empty())); }
    catch { this.broken = true; throw fail(); }
    return true;
  }
  _write(next) {
    if (!this.account) throw fail();
    try { this.store.write(`credit.${this.account}.json`, next); }
    catch { this.broken = true; throw fail(); }
    this.record = next; this.broken = false;
  }
  _current() { if (!this.account || this.broken) throw fail(); return structuredClone(this.record); }

  saveBilling({ creditUSD, pendingUSD, imagePriceUSD = '0.002', observedAt = new Date() }) {
    if (!this.account) throw fail();
    const credit = micros(creditUSD, 2, 1_000_000n * DOLLAR), pending = micros(pendingUSD, 2, 1_000_000n * DOLLAR);
    const price = micros(imagePriceUSD, 6, 1000n * DOLLAR);
    if (price <= 0n) throw fail();
    const next = empty();
    next.billing = { creditMicros: credit.toString(), pendingMicros: pending.toString(), priceMicros: price.toString(), observedAt: iso(observedAt) };
    // Saving a new observation resets money accounting, never the five-image cadence.
    if (!this.broken) { next.completionRemainder = this.record.completionRemainder; next.usage = structuredClone(this.record.usage); }
    this._write(next); return true;
  }

  clearBilling() {
    const next = this.broken ? empty() : this._current();
    next.billing = null; next.localAttempts = '0'; next.accounted = '0'; next.baseline = null;
    next.overflowed = false; next.needsBillingUpdate = false;
    this._write(next); return true;
  }

  recordAttempt(appId) {
    if (!this.account || hashAccount(appId) !== this.account) return false;
    const next = this._current();
    next.localAttempts = cap(BigInt(next.localAttempts) + 1n, next).toString();
    next.accounted = cap(BigInt(next.accounted) + 1n, next).toString();
    this._write(next); return true;
  }

  recordCompletion(appId) {
    if (!this.account || hashAccount(appId) !== this.account) return false;
    const next = this._current();
    next.completionRemainder = (next.completionRemainder + 1) % 5;
    this._write(next); return next.completionRemainder === 0;
  }

  reconcile({ imageCount, periodStart, periodEnd, fetchedAt }) {
    const next = this._current();
    if (!Number.isSafeInteger(imageCount) || imageCount < 0) throw fail();
    const usage = { imageCount, ...period(periodStart, periodEnd), fetchedAt: iso(fetchedAt) };
    if (next.usage && usage.periodStart < next.usage.periodStart) return false;
    if (next.usage && usage.periodStart === next.usage.periodStart) {
      usage.imageCount = Math.max(next.usage.imageCount, usage.imageCount);
      usage.fetchedAt = usage.fetchedAt > next.usage.fetchedAt ? usage.fetchedAt : next.usage.fetchedAt;
    }
    if (next.billing) {
      const price = BigInt(next.billing.priceMicros);
      if (!next.baseline) {
        const reserve = BigInt(next.billing.pendingMicros) + CENT;
        const knownCost = ceilDivide(BigInt(usage.imageCount) * price, CENT) * CENT;
        const precision = knownCost > reserve ? cap(ceilDivide(knownCost - reserve, price), next) : 0n;
        next.accounted = cap(BigInt(next.accounted) + precision, next).toString();
        next.baseline = { periodStart: usage.periodStart, baseCount: String(usage.imageCount), highWater: String(usage.imageCount), priorPeriods: '0', precisionDebits: precision.toString() };
      } else {
        const baseline = next.baseline;
        if (usage.periodStart > baseline.periodStart) {
          baseline.priorPeriods = cap(BigInt(baseline.priorPeriods) + BigInt(baseline.highWater) - BigInt(baseline.baseCount), next).toString();
          baseline.periodStart = usage.periodStart; baseline.baseCount = '0'; baseline.highWater = String(usage.imageCount);
          next.needsBillingUpdate = true;
        } else { baseline.highWater = (BigInt(usage.imageCount) > BigInt(baseline.highWater) ? BigInt(usage.imageCount) : BigInt(baseline.highWater)).toString(); }
        const server = cap(BigInt(baseline.priorPeriods) + BigInt(baseline.highWater) - BigInt(baseline.baseCount) + BigInt(baseline.precisionDebits), next);
        if (server > BigInt(next.accounted)) next.accounted = server.toString();
      }
      if (month(next.billing.observedAt) < usage.periodStart) next.needsBillingUpdate = true;
    }
    next.usage = usage;
    this._write(next); return true;
  }

  snapshot(monthlyImageLimit = 0, now = new Date()) {
    const currentMonth = month(now), r = this.record;
    const hasCurrentUsage = Boolean(r.usage && r.usage.periodStart === currentMonth);
    const monthlyUsed = hasCurrentUsage ? r.usage.imageCount : null;
    const monthlyRemaining = monthlyUsed !== null && Number.isSafeInteger(monthlyImageLimit) && monthlyImageLimit > 0 ? Math.max(0, monthlyImageLimit - monthlyUsed) : null;
    const stale = this.broken || Boolean(r.billing && (r.needsBillingUpdate || month(r.billing.observedAt) !== currentMonth));
    let remaining = null;
    const detail = [];
    if (this.broken) detail.push('额度记录无法读取或保存，暂不显示剩余次数；原文件已保留，请更新账单快照。');
    else if (!this.account) detail.push('请先保存有效的 Mathpix 配置。');
    else if (!r.billing) detail.push('尚未设置 Billing 账单快照。官方 usage 仅提供图片用量，不能查询实时余额。');
    else {
      const b = r.billing, credit = BigInt(b.creditMicros), reserve = BigInt(b.pendingMicros) + CENT, price = BigInt(b.priceMicros);
      const baseline = credit > reserve ? (credit - reserve) / price : 0n;
      const left = baseline > BigInt(r.accounted) ? baseline - BigInt(r.accounted) : 0n;
      remaining = stale ? null : r.overflowed ? 0 : Number(left);
      detail.push(`账单快照 ${b.observedAt}；这是本地保守估算，非实时余额。`);
      detail.push(`抵扣余额 $${money(credit)}；待结算 $${money(BigInt(b.pendingMicros))}，另预留 $0.01；图片单价 $${money(price)}/张。`);
      detail.push(`基础可覆盖次数向下取整；本机每次发送前扣 1 次（含失败及重试）。快照后本机新增 ${r.localAttempts} 次，校准累计扣减 ${r.accounted} 次。`);
      if (r.baseline) detail.push(`初始用量精度差额额外预留 ${r.baseline.precisionDebits} 次；官方用量延迟或回退不会增加剩余，也不重复扣减本机请求。`);
      if (r.overflowed) detail.push('计数超出安全范围，保守显示 0 次，请更新账单快照。');
      if (stale) detail.push('账单快照已跨月或记录异常，需更新 Billing 后显示总剩余；月末未同步消费可能遗漏。');
      detail.push('账单可能延迟，其他设备图片消费由官方用量校准，其他接口或高价图片需重新更新快照。');
    }
    detail.push(`每完成 5 次请求查询一次官方用量，距下次自动校准 ${5 - r.completionRemainder} 次。`);
    if (r.usage && !hasCurrentUsage) detail.push('上次官方用量已过期，等待当前月查询。');
    return { remaining, monthlyUsed, monthlyRemaining, detail: detail.join('\n'), fetchedAt: r.usage?.fetchedAt || null,
      completionRemainder: r.completionRemainder, nextRefreshIn: 5 - r.completionRemainder, stale };
  }
}

module.exports = { CreditStore };
