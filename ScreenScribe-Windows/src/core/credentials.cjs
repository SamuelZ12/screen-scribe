'use strict';

const { createHash } = require('node:crypto');
const FILE = 'credentials.json';
const MAX_CIPHER_BYTES = 20_000;
function fail() { const error = new Error('无法安全读取或保存凭据。请检查 Windows 加密存储状态并重新保存配置。'); error.safeMessage = error.message; return error; }
function scope(provider, baseURL) {
  if (provider === 'mathpix') return 'mathpix';
  if (provider !== 'vision') throw fail();
  try {
    const url = new URL(baseURL);
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) throw fail();
    const normalized = url.toString().replace(/\/+$/, '');
    return `vision.${createHash('sha256').update(normalized).digest('hex')}`;
  } catch { throw fail(); }
}
function text(value, max) {
  if (typeof value !== 'string' || !value.trim() || value.length > max || /[\x00-\x1f\x7f]/.test(value)) throw fail();
  return value.trim();
}
function credentials(provider, value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw fail();
  const apiKey = text(value.apiKey, 8192);
  return provider === 'mathpix' ? { appId: text(value.appId, 512), apiKey } : { apiKey };
}
function read(store) {
  const data = store.read(FILE, { version: 1, entries: {} });
  if (!data || data.version !== 1 || !data.entries || typeof data.entries !== 'object' || Array.isArray(data.entries)) throw fail();
  const entries = Object.create(null);
  for (const [key, value] of Object.entries(data.entries)) {
    if (!/^(mathpix|vision\.[a-f0-9]{64})$/.test(key) || typeof value !== 'string' || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value) ||
        !value.length || value.length > MAX_CIPHER_BYTES * 1.34 || Buffer.from(value, 'base64').length > MAX_CIPHER_BYTES) throw fail();
    entries[key] = value;
  }
  return { version: 1, entries };
}

class CredentialVault {
  constructor(store, cryptoAdapter) { this.store = store; this.crypto = cryptoAdapter; }

  async load(provider, baseURL) {
    try {
      const key = scope(provider, baseURL), data = read(this.store);
      if (!Object.hasOwn(data.entries, key)) return null;
      if (!await this.crypto.available()) throw fail();
      const plain = await this.crypto.decrypt(Buffer.from(data.entries[key], 'base64'));
      if (typeof plain !== 'string' || plain.length > 12_000) throw fail();
      return credentials(provider, JSON.parse(plain));
    } catch { throw fail(); }
  }

  async save(provider, value, baseURL) {
    try {
      const key = scope(provider, baseURL), plain = JSON.stringify(credentials(provider, value));
      if (!await this.crypto.available()) throw fail();
      const encrypted = await this.crypto.encrypt(plain);
      if (!Buffer.isBuffer(encrypted) || !encrypted.length || encrypted.length > MAX_CIPHER_BYTES || encrypted.equals(Buffer.from(plain))) throw fail();
      const data = read(this.store);
      data.entries[key] = encrypted.toString('base64');
      this.store.write(FILE, data);
      return true;
    } catch { throw fail(); }
  }

  async remove(provider, baseURL) {
    try {
      const key = scope(provider, baseURL), data = read(this.store);
      if (Object.hasOwn(data.entries, key)) { delete data.entries[key]; this.store.write(FILE, data); }
      return true;
    } catch { throw fail(); }
  }

  async status(provider, baseURL) { return (await this.load(provider, baseURL)) !== null; }
}

module.exports = { CredentialVault };
