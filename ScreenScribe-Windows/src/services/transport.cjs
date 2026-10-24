'use strict';

const https = require('node:https');

const MESSAGES = Object.freeze({
  configuration: '请检查此识别服务的地址、模型及 API 凭据。',
  image: '图片格式无效或超过后端上传限制。请缩小框选区域。未上传图片。',
  malformed: '响应格式不符合要求或输出被截断。请核对服务的视觉支持后重试。',
  network: '网络连接失败或请求超时。请检查网络后重试。',
  cancelled: '已取消。',
  rejected: '服务返回了识别错误。请检查图片、凭据及服务控制台。',
  noMath: '未返回可验证的 LaTeX 数学字段。请只框选公式后重试。',
  incomplete: 'Mathpix 用量数据可能不完整，请查看控制台。',
  local: '本地额度记录未完成，请检查数据目录后重试。'
});

class ServiceError extends Error {
  constructor(code, status) {
    let message = MESSAGES[code] || MESSAGES.network;
    if (code === 'http') {
      if (status === 401 || status === 403) message = '认证失败，请检查此服务的 API 凭据及访问权限。';
      else if (status === 429) message = '请求被限流或余额不足（HTTP 429）。请查看服务控制台后重试。';
      else message = `服务请求失败（HTTP ${Number.isInteger(status) ? status : 0}）。请检查端点、模型和服务状态。`;
    }
    super(message);
    this.name = 'ServiceError';
    this.code = code;
    this.safeMessage = message;
    if (code === 'http' && Number.isInteger(status)) this.status = status;
  }
}

function fail(code, status) { return new ServiceError(code, status); }
function checkCancelled(signal) { if (signal?.aborted) throw fail('cancelled'); }
function safeError(error, signal) {
  if (signal?.aborted) return fail('cancelled');
  // Only our own errors cross the service boundary; request URLs, response bodies,
  // OS errors and authorization headers must never become UI/log messages.
  return error instanceof ServiceError ? error : fail('network');
}

function isObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }

// Exposed separately for deterministic stream-level tests. It never follows a
// redirect, never retries, and applies both a total deadline and a byte limit.
function createJSONTransport(requestImplementation = https.request) {
  return function transport({ url, method, headers, body, signal, timeoutMs = 60_000 }) {
    return new Promise((resolve, reject) => {
      let parsedURL;
      try {
        parsedURL = new URL(url);
        if (parsedURL.protocol !== 'https:' || parsedURL.username || parsedURL.password || parsedURL.hash) throw fail('configuration');
        checkCancelled(signal);
      } catch (error) { reject(error instanceof ServiceError ? error : fail('configuration')); return; }
      if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 120_000) { reject(fail('configuration')); return; }
      let settled = false;
      let request;
      let response;
      const finish = (error, value) => {
        if (settled) return;
        settled = true;
        clearTimeout(deadline);
        signal?.removeEventListener('abort', abort);
        if (error) reject(safeError(error, signal)); else resolve(value);
      };
      const stop = (error) => {
        finish(error);
        response?.destroy();
        request?.destroy();
      };
      const abort = () => stop(fail('cancelled'));
      const deadline = setTimeout(() => stop(fail('network')), timeoutMs);
      signal?.addEventListener('abort', abort, { once: true });
      try {
        request = requestImplementation(parsedURL, {
          method, headers, agent: false, maxHeaderSize: 16_384, rejectUnauthorized: true
        }, (incoming) => {
          response = incoming;
          if (settled) { incoming.destroy(); return; }
          const status = incoming.statusCode;
          if (!Number.isInteger(status) || status < 200 || status >= 300) { stop(fail('http', status)); return; }
          const encoding = incoming.headers?.['content-encoding'];
          // We do not request compression. Refuse unexpected encodings rather
          // than allowing compressed responses to bypass the decoded byte limit.
          if (encoding && encoding !== 'identity') { stop(fail('malformed')); return; }
          const maximum = 2_000_000;
          const declared = incoming.headers?.['content-length'];
          if (declared !== undefined && (!/^\d+$/.test(String(declared)) || Number(declared) > maximum)) { stop(fail('malformed')); return; }
          let length = 0;
          const chunks = [];
          incoming.on('data', (chunk) => {
            if (settled) return;
            const data = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
            length += data.length;
            if (length > maximum) { stop(fail('malformed')); return; }
            chunks.push(data);
          });
          incoming.on('error', () => stop(fail('network')));
          incoming.on('aborted', () => stop(fail('network')));
          incoming.on('end', () => {
            if (settled) return;
            try {
              if (declared !== undefined && Number(declared) !== length) throw fail('malformed');
              const value = JSON.parse(Buffer.concat(chunks, length).toString('utf8'));
              if (!isObject(value)) throw fail('malformed');
              finish(null, value);
            } catch { finish(fail('malformed')); }
          });
        });
        request.on('error', () => finish(fail('network')));
        // A cancellation could arrive while constructing the request.
        if (signal?.aborted) { abort(); return; }
        request.end(body);
      } catch (error) { stop(safeError(error, signal)); }
    });
  };
}

const defaultTransport = createJSONTransport();

// Also bound injected transports, so a cancellation cannot leave recognition
// spinning forever even if a test/custom transport ignores AbortSignal.
async function sendJSON(options, injected) {
  checkCancelled(options.signal);
  const timeoutMs = options.timeoutMs || 60_000;
  const controller = new AbortController();
  const forwardAbort = () => controller.abort();
  options.signal?.addEventListener('abort', forwardAbort, { once: true });
  let timer;
  let onAbort;
  const boundary = new Promise((_, reject) => {
    onAbort = () => reject(fail(options.signal?.aborted ? 'cancelled' : 'network'));
    controller.signal.addEventListener('abort', onAbort, { once: true });
    timer = setTimeout(() => controller.abort(), timeoutMs);
  });
  try {
    const value = await Promise.race([
      (injected || defaultTransport)({ ...options, signal: controller.signal, timeoutMs }), boundary
    ]);
    checkCancelled(options.signal);
    if (!isObject(value)) throw fail('malformed');
    return value;
  } catch (error) { throw safeError(error, options.signal); }
  finally {
    clearTimeout(timer);
    controller.signal.removeEventListener('abort', onAbort);
    options.signal?.removeEventListener('abort', forwardAbort);
  }
}

module.exports = { ServiceError, fail, checkCancelled, safeError, isObject, createJSONTransport, sendJSON };
