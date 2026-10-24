'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { randomBytes } = require('node:crypto');

const MAX_BYTES = 32_000_000;
function fail(code, message) { const error = new Error(message); error.code = code; error.safeMessage = message; return error; }
function validateName(name) {
  if (typeof name !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(name) ||
      name.endsWith('.') || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(name)) {
    throw fail('STORE_NAME_INVALID', '本地存储文件名无效。');
  }
}

class JsonFileStore {
  constructor(baseDir) {
    if (typeof baseDir !== 'string' || !path.isAbsolute(baseDir)) throw fail('STORE_DIRECTORY_INVALID', '本地存储目录无效。');
    this.baseDir = path.resolve(baseDir);
  }

  _directory(create) {
    if (create) fs.mkdirSync(this.baseDir, { recursive: true, mode: 0o700 });
    const info = fs.lstatSync(this.baseDir);
    if (!info.isDirectory() || info.isSymbolicLink()) throw new Error('Unsafe storage directory');
    if (create && process.platform !== 'win32') fs.chmodSync(this.baseDir, 0o700);
  }

  read(name, fallback) {
    validateName(name);
    let fd;
    try {
      this._directory(false);
      const file = path.join(this.baseDir, name);
      const info = fs.lstatSync(file);
      if (!info.isFile() || info.isSymbolicLink() || info.size > MAX_BYTES) throw new Error('Unsafe storage file');
      fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
      const opened = fs.fstatSync(fd);
      if (!opened.isFile() || opened.size > MAX_BYTES || opened.dev !== info.dev || opened.ino !== info.ino) throw new Error('Storage file changed');
      const contents = fs.readFileSync(fd, 'utf8');
      if (Buffer.byteLength(contents) > MAX_BYTES) throw new Error('Storage file too large');
      try { return JSON.parse(contents); } catch { throw fail('STORE_CORRUPT', '本地数据损坏，原文件已保留。'); }
    } catch (error) {
      if (error.code === 'ENOENT') return fallback === undefined ? undefined : structuredClone(fallback);
      if (error.code === 'STORE_CORRUPT') throw error;
      throw fail('STORE_READ_FAILED', '无法读取本地数据，原文件已保留。');
    } finally { if (fd !== undefined) fs.closeSync(fd); }
  }

  write(name, value) {
    validateName(name);
    let temporary, fd;
    try {
      const contents = JSON.stringify(value);
      if (typeof contents !== 'string' || Buffer.byteLength(contents) > MAX_BYTES) throw new Error('Invalid storage data');
      this._directory(true);
      const file = path.join(this.baseDir, name);
      try {
        const info = fs.lstatSync(file);
        if (!info.isFile() || info.isSymbolicLink()) throw new Error('Unsafe storage file');
      } catch (error) { if (error.code !== 'ENOENT') throw error; }
      temporary = path.join(this.baseDir, `.${name}.${randomBytes(12).toString('hex')}.tmp`);
      fd = fs.openSync(temporary, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL, 0o600);
      fs.writeFileSync(fd, contents, 'utf8');
      if (process.platform !== 'win32') fs.fchmodSync(fd, 0o600);
      fs.fsyncSync(fd);
      fs.closeSync(fd); fd = undefined;
      fs.renameSync(temporary, file);
      temporary = undefined;
    } catch {
      throw fail('STORE_WRITE_FAILED', '无法保存本地数据，请检查目录权限与磁盘空间。');
    } finally {
      if (fd !== undefined) { try { fs.closeSync(fd); } catch {} }
      if (temporary) { try { fs.unlinkSync(temporary); } catch {} }
    }
  }
}

module.exports = { JsonFileStore };
