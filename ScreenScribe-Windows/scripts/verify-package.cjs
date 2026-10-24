'use strict';

// Inspect a built Windows artifact on any Node >=22 host. This is a static
// package audit, not evidence that Windows capture/DPAPI/installation ran.
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const asar = require('@electron/asar');
const ROOT = path.resolve(__dirname, '..');
const input = path.resolve(ROOT, process.argv[2] || 'dist/win-unpacked');
const artifactDirectory = path.join(ROOT, 'artifacts');
const report = { ok: false, checkedAt: new Date().toISOString(), kind: 'static-windows-package-audit', windowsRuntimeVerified: false, checks: [], errors: [] };
class AuditFailure extends Error {}
function check(name, condition) {
  report.checks.push({ name, passed: Boolean(condition) });
  if (!condition) throw new AuditFailure(name);
}
function fileInside(base, name) {
  const file = path.join(base, name), relative = path.relative(base, file);
  if (relative.startsWith('..') || path.isAbsolute(relative)) throw new AuditFailure('safe package path');
  const info = fs.lstatSync(file);
  if (!info.isFile() || info.isSymbolicLink()) throw new AuditFailure('regular package file');
  return file;
}
function peInfo(file) {
  const fd = fs.openSync(file, 'r');
  try {
    const size = fs.fstatSync(fd).size, dos = Buffer.alloc(64);
    if (size < 128 || fs.readSync(fd, dos, 0, 64, 0) !== 64 || dos.readUInt16LE(0) !== 0x5a4d) throw new AuditFailure('Windows MZ executable header');
    const offset = dos.readUInt32LE(0x3c), header = Buffer.alloc(26);
    if (offset < 64 || offset > size - 26 || fs.readSync(fd, header, 0, 26, offset) !== 26 || header.readUInt32LE(0) !== 0x00004550) throw new AuditFailure('Windows PE signature');
    const machine = header.readUInt16LE(4), characteristics = header.readUInt16LE(22), magic = header.readUInt16LE(24);
    if (!(characteristics & 0x0002) || characteristics & 0x2000 || magic !== 0x020b) throw new AuditFailure('64-bit executable image');
    const arch = machine === 0x8664 ? 'x64' : machine === 0xaa64 ? 'arm64' : null;
    if (!arch) throw new AuditFailure('x64 or arm64 machine architecture');
    return { architecture: arch, machine: `0x${machine.toString(16)}`, bytes: size };
  } finally { fs.closeSync(fd); }
}
function privatePath(name) {
  const p = name.replace(/\\/g, '/');
  return /(?:^|\/)(?:\.git|\.local-signing|\.cache|cache|tests?|fixtures?|user-?data|data|artifacts|build)(?:\/|$)/i.test(p) ||
    /(?:^|\/)(?:\.env(?:\.[^/]*)?|secrets?\.(?:json|plist|ya?ml)|credentials\.json|settings\.json|history\.json|credit\.[a-f0-9]{64}\.json|OPERATION-AUDIT\.md|TEST-RESULTS\.md)$/i.test(p) ||
    /\.(?:p12|pfx|pem|key|keychain(?:-db)?|log)$/i.test(p);
}
function walk(directory, prefix = '', output = []) {
  for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
    const relative = prefix ? `${prefix}/${item.name}` : item.name;
    if (item.isSymbolicLink()) throw new AuditFailure('no package symbolic links');
    if (privatePath(relative)) throw new AuditFailure('no private files in Windows package');
    if (item.isDirectory()) walk(path.join(directory, item.name), relative, output);
    else if (item.isFile()) output.push(relative);
    else throw new AuditFailure('regular package files only');
    if (output.length > 10000) throw new AuditFailure('bounded package file inventory');
  }
  return output;
}
function containsPrivateLiteral(text) {
  // Match actual literals/known local roots, not incidental words such as key
  // in KaTeX, DLLs, variable names or a user's future empty settings field.
  return /(?:\/Users\/|C:\\\\Users\\\\|-----BEGIN (?:[A-Z ]*PRIVATE KEY|CERTIFICATE)-----)/.test(text) ||
    /(?:apiKey|app_key|app_id)\s*['"]?\s*:\s*['"][^'"\r\n]+['"]/.test(text);
}
async function digest(file) {
  const hash = createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}
async function main() {
  const archive = fileInside(input, 'resources/app.asar');
  const executable = fileInside(input, 'ScreenScribe.exe');
  report.executable = peInfo(executable); check('Windows MZ/PE64 x64 or arm64 executable', true);
  const diskFiles = walk(input); check('No private credentials/signing/test/cache/data files on disk', true);
  const paths = asar.listPackage(archive).map(name => name.replace(/^[/\\]+/, '').replace(/\\/g, '/'));
  const files = [];
  for (const name of paths) {
    check('ASAR paths stay within application archive', !name.startsWith('../') && !name.includes('/../') && !name.includes('\0'));
    if (!name) continue;
    const info = asar.statFile(archive, name, false);
    if (info.link) throw new AuditFailure('no ASAR symbolic links');
    if (info.files) continue;
    if (privatePath(name)) throw new AuditFailure('no private files in ASAR');
    if (!/^(?:src\/|assets\/|package\.json$|LICENSE$|THIRD-PARTY-NOTICES\.md$)/.test(name)) throw new AuditFailure('explicit application file allowlist');
    files.push(name);
  }
  const required = ['package.json', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'src/main.cjs', 'src/preload.cjs', 'src/core/controller.cjs',
    'src/core/storage.cjs', 'src/core/os-crypto.cjs', 'src/core/credentials.cjs', 'src/core/history.cjs', 'src/core/credit.cjs', 'src/core/settings.cjs',
    'src/services/providers.cjs', 'src/services/transport.cjs', 'src/services/latex.cjs', 'src/capture/geometry.cjs',
    'src/capture/overlay.html', 'src/capture/overlay.js', 'src/capture/overlay.css', 'src/capture/preload.cjs',
    'src/renderer/index.html', 'src/renderer/app.js', 'src/renderer/styles.css', 'assets/vendor/katex.min.js', 'assets/vendor/katex.min.css', 'assets/vendor/LICENSE-KaTeX.txt',
    'assets/icon.png', 'assets/tray.png', 'assets/test-equation.png', 'assets/native-pattern.html', 'assets/native-pattern.js'];
  for (const name of required) check(`Required packed resource: ${name}`, files.includes(name) && !asar.statFile(archive, name, false).unpacked && asar.statFile(archive, name, false).size > 0);
  check('Offline preview fonts are bundled', files.filter(name => /^assets\/vendor\/fonts\/.*\.(?:woff2?|ttf)$/.test(name)).length >= 20);
  check('Chinese help is bundled', diskFiles.includes('resources/使用说明.txt'));
  const read = name => asar.extractFile(archive, name).toString('utf8');
  const metadata = JSON.parse(read('package.json')), expected = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));
  check('Packaged application version and entry point match project', metadata.version === expected.version && metadata.name === expected.name && metadata.main === 'src/main.cjs');
  report.version = metadata.version;
  for (const name of files.filter(name => name.startsWith('src/') && /\.(?:cjs|js|html|css)$/.test(name))) {
    const text = read(name);
    if (containsPrivateLiteral(text)) throw new AuditFailure('no embedded local paths or credential literals');
    if (/(?:nodeIntegration(?:InWorker|InSubFrames)?|enableRemoteModule|allowRunningInsecureContent)\s*:\s*true\b|(?:contextIsolation|sandbox|webSecurity|rejectUnauthorized)\s*:\s*false\b|@electron\/remote|ignore-certificate-errors/.test(text)) throw new AuditFailure('no insecure Electron or TLS switches');
  }
  check('Application source contains no private literals or insecure switches', true);
  const mainSource = read('src/main.cjs'), preload = read('src/preload.cjs'), capturePreload = read('src/capture/preload.cjs'), renderer = read('src/renderer/app.js');
  for (const [label, pattern] of Object.entries({ sandbox: /sandbox\s*:\s*true/, contextIsolation: /contextIsolation\s*:\s*true/, noNodeIntegration: /nodeIntegration\s*:\s*false/, webSecurity: /webSecurity\s*:\s*true/, permissionDenied: /setPermissionCheckHandler\(\s*\(\)\s*=>\s*false\s*\)/, deniedWindows: /setWindowOpenHandler\([\s\S]*?action\s*:\s*['"]deny['"]/, navigationGuard: /will-navigate/, rendererOriginGuard: /event\.senderFrame\s*===\s*window\.webContents\.mainFrame/, isolatedWindowPreferences: /webPreferences\s*:\s*prefs\(/ })) check(`Main process static guard: ${label}`, pattern.test(mainSource));
  check('Main and capture windows use shared isolated preferences', (mainSource.match(/new BrowserWindow\(/g) || []).length === (mainSource.match(/webPreferences\s*:\s*prefs\(/g) || []).length);
  check('Preloads expose restricted bridges', /contextBridge\.exposeInMainWorld\(['"]screenScribe['"]/.test(preload) && /commands\.has\(name\)/.test(preload) && /contextBridge\.exposeInMainWorld\(/.test(capturePreload));
  check('Renderer uses offline KaTeX with trust disabled', /window\.katex\.render\(/.test(renderer) && /trust\s*:\s*false/.test(renderer));
  for (const name of ['src/renderer/index.html', 'src/capture/overlay.html']) {
    const html = read(name);
    check(`Strict local CSP: ${name}`, /Content-Security-Policy/i.test(html) && /default-src 'none'/.test(html) && /script-src 'self'/.test(html) && /connect-src 'none'/.test(html) && /object-src 'none'/.test(html) && !/<(?:script|link)[^>]+(?:src|href)\s*=\s*['"]https?:/i.test(html));
  }
  report.archive = { sha256: await digest(archive), bytes: fs.statSync(archive).size, fileCount: files.length };
  report.executable.sha256 = await digest(executable);
  report.ok = true;
}
main().catch(error => { report.errors.push(error instanceof AuditFailure ? error.message : 'Windows package audit did not pass; inspect package structure and static guards.'); process.exitCode = 1; }).finally(() => {
  fs.mkdirSync(artifactDirectory, { recursive: true, mode: 0o700 });
  const file = path.join(artifactDirectory, 'package-verification.json');
  fs.writeFileSync(file, JSON.stringify(report, null, 2) + '\n', { mode: 0o600 });
  console.log(JSON.stringify({ ok: report.ok, version: report.version, architecture: report.executable?.architecture, passedChecks: report.checks.filter(check => check.passed).length, windowsRuntimeVerified: false, report: 'artifacts/package-verification.json', errors: report.errors }));
});
