'use strict';

const { randomUUID } = require('node:crypto');
const FILE = 'history.json';
const MAX_BYTES = 25_000_000;
const MAX_ENTRIES = 50;
const PNG_PREFIX = 'data:image/png;base64,';
const PNG_MAGIC = Buffer.from('89504e470d0a1a0a', 'hex');
function fail() { const error = new Error('历史记录无法读取或保存，原文件已保留。可明确清空历史后恢复。'); error.safeMessage = error.message; return error; }
function string(value, max, defaultValue = '') {
  if (value === undefined) return defaultValue;
  if (typeof value !== 'string' || Buffer.byteLength(value) > max) throw fail();
  return value;
}
function clean(entry, persistImages) {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) throw fail();
  const id = entry.id === undefined ? randomUUID() : string(entry.id, 100);
  if (!/^[A-Za-z0-9_-]{1,100}$/.test(id)) throw fail();
  const date = entry.createdAt === undefined ? new Date() : new Date(entry.createdAt);
  if (Number.isNaN(date.getTime()) || !['mathpix', 'vision'].includes(entry.provider) || !['equation', 'feynman'].includes(entry.mode)) throw fail();
  const result = {
    id, createdAt: date.toISOString(), mode: entry.mode, provider: entry.provider,
    model: string(entry.model, 400), code: string(entry.code, 1_000_000), structure: string(entry.structure, 100_000),
    warnings: [], confidence: entry.confidence === undefined ? null : entry.confidence
  };
  if (result.confidence !== null && (typeof result.confidence !== 'number' || !Number.isFinite(result.confidence) || result.confidence < 0 || result.confidence > 1)) throw fail();
  if (entry.warnings !== undefined) {
    if (!Array.isArray(entry.warnings) || entry.warnings.length > 50) throw fail();
    result.warnings = entry.warnings.map(value => string(value, 2000));
  }
  if (persistImages && entry.imageDataUrl !== undefined) {
    const image = string(entry.imageDataUrl, 15_000_000);
    const encoded = image.slice(PNG_PREFIX.length);
    if (!image.startsWith(PNG_PREFIX) || !encoded.length || encoded.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) throw fail();
    const data = Buffer.from(encoded, 'base64');
    if (data.length > 10_000_000 || data.length < 8 || data.toString('base64') !== encoded || !data.subarray(0, 8).equals(PNG_MAGIC)) throw fail();
    result.imageDataUrl = image;
  }
  return result;
}
function size(entries) { return Buffer.byteLength(JSON.stringify(entries)); }
function cap(entries) {
  const next = entries.slice(0, MAX_ENTRIES);
  while (next.length > 1 && size(next) > MAX_BYTES) next.pop();
  if (size(next) > MAX_BYTES) throw fail();
  return next;
}

class HistoryStore {
  constructor(store) {
    this.store = store; this.entries = []; this.error = ''; this.loadFailed = false;
    try {
      const data = store.read(FILE, []);
      if (!Array.isArray(data) || data.length > MAX_ENTRIES || size(data) > MAX_BYTES) throw fail();
      this.entries = data.map(entry => clean(entry, true));
      if (new Set(this.entries.map(entry => entry.id)).size !== this.entries.length) throw fail();
    } catch { this.loadFailed = true; this.entries = []; this.error = fail().message; }
  }

  list() { return structuredClone(this.entries); }
  _persist(entries) {
    if (this.loadFailed) throw fail();
    try { this.store.write(FILE, entries); this.entries = entries; this.error = ''; }
    catch { this.error = fail().message; throw fail(); }
  }
  add(entry, { persistImages = false } = {}) {
    const next = clean(entry, persistImages === true);
    this._persist(cap([next, ...this.entries.filter(item => item.id !== next.id)]));
    return structuredClone(next);
  }
  update(id, code) {
    const found = this.entries.find(entry => entry.id === id);
    if (!found) return null;
    const next = clean({ ...found, code }, true);
    this._persist(cap(this.entries.map(entry => entry.id === id ? next : entry)));
    return structuredClone(next);
  }
  remove(id) { this._persist(this.entries.filter(entry => entry.id !== id)); }
  removeImages() { this._persist(this.entries.map(({ imageDataUrl, ...entry }) => entry)); }
  clear() {
    const failed = this.loadFailed; this.loadFailed = false;
    try { this._persist([]); } catch (error) { this.loadFailed = failed; throw error; }
  }
}

module.exports = { HistoryStore };
