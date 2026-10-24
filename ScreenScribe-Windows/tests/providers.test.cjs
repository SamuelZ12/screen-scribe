'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { normalizeVisionBase, recognizeMathpix, recognizeVision, fetchMathpixUsage, formatSource } = require('../src/services/providers.cjs');
const { createJSONTransport, sendJSON, fail } = require('../src/services/transport.cjs');
const { balanced } = require('../src/services/latex.cjs');

// Public 1x1 PNG fixture, no local screenshots or credential reads.
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jH6kAAAAASUVORK5CYII=', 'base64');
const credentials = { appId: 'unit-test-app', apiKey: 'unit-test-fake-key' };
const SECRET_ECHO = 'unit-test-response-secret-must-not-appear';
const vision = { png, apiKey: 'unit-test-vision-key', baseURL: 'https://vision.example.test/v1/', model: 'test-vision', mode: 'equation' };
const response = (content, finish_reason = 'stop') => ({ choices: [{ finish_reason, message: { content } }] });
const diagram = String.raw`\documentclass[tikz,border=2pt]{standalone}
\usepackage{tikz-feynman,amsmath}
\begin{document}
\begin{tikzpicture}
\begin{feynman}
\vertex (a) at (0,0);
\vertex (b) at (2,0);
\diagram*{(a)--[photon](b)};
\end{feynman}
\end{tikzpicture}
\end{document}`;
const diagramJSON = (code = diagram, extra = {}) => JSON.stringify({ code, structure: 'a 与 b 由波浪线连接，粒子身份待确认。', uncertainties: ['箭头方向不可读'], ...extra });

function mock(value) {
  const requests = [];
  const transport = async (request) => { requests.push(request); return value; };
  return { transport, requests };
}
function rejectsSafe(errorCode) {
  return (error) => {
    assert.equal(error.code, errorCode);
    assert.ok(!error.message.includes(SECRET_ECHO));
    assert.ok(!error.stack.includes(SECRET_ECHO));
    return true;
  };
}

test('Mathpix sends only selected PNG with mature compact-source options and header credentials', async () => {
  const probe = mock({ latex_styled: String.raw`\[\begin{aligned}a&=b\\c&=d\end{aligned}\]`, confidence: 0.8,
    line_data: [{ confidence: 0.7, text: 'l or 1', conversion_output: false }] });
  const order = [];
  const output = await recognizeMathpix({ png, ...credentials, transport: async (request) => {
    order.push('transport'); return probe.transport(request);
  }, beforeSend: () => { order.push('before'); }, afterSend: () => { order.push('after'); } });
  assert.deepEqual(order, ['before', 'transport', 'after']);
  assert.equal(probe.requests.length, 1);
  const request = probe.requests[0];
  assert.equal(request.url, 'https://api.mathpix.com/v3/text');
  assert.equal(request.method, 'POST');
  assert.equal(request.headers.app_id, credentials.appId);
  assert.equal(request.headers.app_key, credentials.apiKey);
  assert.ok(!request.url.includes(credentials.apiKey));
  assert.deepEqual(JSON.parse(request.body), {
    src: `data:image/png;base64,${png.toString('base64')}`, formats: ['latex_styled', 'data'],
    data_options: { include_latex: true }, include_line_data: true,
    rm_spaces: true, idiomatic_braces: true, idiomatic_eqn_arrays: false
  });
  assert.equal(output.code, String.raw`\begin{aligned}a&=b\\c&=d\end{aligned}`);
  assert.equal(output.structure, '');
  assert.equal(output.confidence, 0.8);
  assert.ok(output.warnings.some((item) => item.includes('80%')));
  assert.ok(output.warnings.some((item) => item.includes('l or 1')));
  assert.ok(output.warnings.some((item) => item.includes('未转换行')));
});

test('Mathpix preserves meaningful text spaces, fonts, explicit spacing and independent math fragments', async () => {
  const source = String.raw`\text{ a  b }+\mathrm{d}x+\alpha x+\,y\quad z`;
  assert.equal((await recognizeMathpix({ png, ...credentials, ...mock({ error: null, error_info: null, latex_styled: source }) })).code, source);
  const probe = mock({ data: [{ type: 'latex', value: '$a=b$' }, { type: 'text', value: 'ignored' }, { type: 'latex', value: 'c=d' }] });
  const result = await recognizeMathpix({ png, ...credentials, ...probe });
  assert.equal(result.code, '\\begin{gathered}\na=b \\\\\nc=d\n\\end{gathered}');
  assert.ok(result.warnings.some((item) => item.includes('跨行对齐')));
  assert.equal(result.confidence, null);
});

test('Mathpix known errors are actionable without echoing response text', async () => {
  for (const id of ['opts_conflict', 'image_no_content', 'math_confidence']) {
    await assert.rejects(recognizeMathpix({ png, ...credentials,
      ...mock({ error: SECRET_ECHO, error_info: { id, message: SECRET_ECHO } }) }), rejectsSafe(id));
  }
  await assert.rejects(recognizeMathpix({ png, ...credentials,
    ...mock({ latex_styled: credentials.apiKey }) }), rejectsSafe('malformed'));
  for (const value of [{ error: SECRET_ECHO }, { error: true }, { error_info: SECRET_ECHO }, { error_info: [] }]) {
    await assert.rejects(recognizeMathpix({ png, ...credentials, ...mock(value) }), rejectsSafe('rejected'));
  }
  for (const value of [{ text: 'some prose' }, {}, { latex_styled: '$$ $$' }, { data: [{ type: 'latex', value: '  ' }] }]) {
    await assert.rejects(recognizeMathpix({ png, ...credentials, ...mock(value) }), rejectsSafe('noMath'));
  }
});

test('Mathpix exactly one completion for each sent success, parse, HTTP, network or cancelled attempt', async () => {
  for (const outcome of ['success', 'parse', 'http', 'network', 'cancel']) {
    const order = [];
    const controller = new AbortController();
    const promise = recognizeMathpix({ png, ...credentials, signal: controller.signal,
      beforeSend: async () => { order.push('before'); }, afterSend: async () => { order.push('after'); },
      transport: async () => {
        order.push('transport');
        if (outcome === 'parse') return [];
        if (outcome === 'http') throw fail('http', 401);
        if (outcome === 'network') throw Error(SECRET_ECHO);
        if (outcome === 'cancel') { controller.abort(); return new Promise(() => {}); }
        return { latex_styled: 'x' };
      }
    });
    if (outcome === 'success') assert.equal((await promise).code, 'x');
    else await assert.rejects(promise, rejectsSafe({ parse: 'malformed', http: 'http', network: 'network', cancel: 'cancelled' }[outcome]));
    assert.deepEqual(order, ['before', 'transport', 'after']);
  }
});

test('invalid inputs and pre-cancelled requests never reserve, complete or send', async () => {
  const huge = Buffer.alloc(1_500_001); png.copy(huge);
  const dimensions = Buffer.from(png); dimensions.writeUInt32BE(0, 16);
  for (const patch of [
    { png: Buffer.alloc(0) }, { png: Buffer.from('not png') }, { png: huge }, { png: dimensions },
    { appId: '' }, { appId: ' \n' }, { appId: 'test\rid' }, { apiKey: '' }, { apiKey: 'a\nb' },
    { apiKey: '  ' }, { apiKey: '中文' }, { afterSend: false }
  ]) {
    let calls = 0;
    const unexpected = () => { calls++; };
    await assert.rejects(recognizeMathpix({ png, ...credentials, beforeSend: unexpected, afterSend: unexpected,
      transport: unexpected, ...patch }));
    assert.equal(calls, 0);
  }
  const controller = new AbortController(); controller.abort();
  let calls = 0;
  await assert.rejects(recognizeMathpix({ png, ...credentials, signal: controller.signal,
    beforeSend: () => { calls++; }, afterSend: () => { calls++; }, transport: () => { calls++; } }), rejectsSafe('cancelled'));
  assert.equal(calls, 0);
});

test('cancellation or store failure during reservation prevents sending and does not fake completion', async () => {
  const order = [];
  const controller = new AbortController();
  await assert.rejects(recognizeMathpix({ png, ...credentials, signal: controller.signal,
    beforeSend: () => { order.push('before'); controller.abort(); },
    afterSend: () => { order.push('after'); }, transport: () => { order.push('transport'); } }), rejectsSafe('cancelled'));
  assert.deepEqual(order, ['before']);
  await assert.rejects(recognizeMathpix({ png, ...credentials,
    beforeSend: () => { throw Error(SECRET_ECHO); }, transport: () => assert.fail('unsent') }), rejectsSafe('local'));
  await assert.rejects(recognizeMathpix({ png, ...credentials, ...mock({ latex_styled: 'x' }),
    afterSend: () => { throw Error(SECRET_ECHO); } }), rejectsSafe('local'));
});

test('base URL normalization binds credentials to a strict HTTPS root', () => {
  assert.equal(normalizeVisionBase('  https://VISION.EXAMPLE.test:443/v1///  '), 'https://vision.example.test/v1');
  assert.equal(normalizeVisionBase('https://vision.example.test/'), 'https://vision.example.test');
  for (const value of [null, '', 'https:example.test/v1', 'http://example.test/v1', 'https://u:p@example.test/v1',
    'https://@example.test/v1', 'https://example.test/v1?', 'https://example.test/v1#',
    'https://example.test/v1?key=fake', 'https://example.test/v1/chat/completions/',
    'https://example.test/v1/responses', 'https://example.test/v1/%63hat/completions',
    'https://example.test\\@elsewhere.test', 'https://example.test/path with spaces', 'https://example.test/%GG']) {
    assert.throws(() => normalizeVisionBase(value), rejectsSafe('configuration'));
  }
});

test('vision sends only selected image, distinct prompts and endpoint-bound bearer key', async () => {
  for (const mode of ['equation', 'feynman']) {
    const probe = mock(response(mode === 'equation' ? String.raw`\[\begin{aligned}a&=b\\c&=d\end{aligned}\]` : diagramJSON()));
    const output = await recognizeVision({ ...vision, mode, ...probe });
    assert.equal(probe.requests.length, 1);
    const request = probe.requests[0];
    assert.equal(request.url, 'https://vision.example.test/v1/chat/completions');
    assert.equal(request.headers.Authorization, `Bearer ${vision.apiKey}`);
    assert.ok(!request.url.includes(vision.apiKey));
    assert.equal(request.headers.app_id, undefined);
    assert.equal(request.headers.app_key, undefined);
    const payload = JSON.parse(request.body);
    assert.equal(payload.model, vision.model);
    assert.equal(payload.stream, false);
    assert.equal(payload.max_completion_tokens, 8192);
    assert.match(payload.messages[0].content, /untrusted data/);
    assert.deepEqual(payload.messages[1].content[1], { type: 'image_url', image_url: { url: `data:image/png;base64,${png.toString('base64')}`, detail: 'high' } });
    if (mode === 'equation') assert.equal(output.code, String.raw`\begin{aligned}a&=b\\c&=d\end{aligned}`);
    else {
      assert.match(payload.messages[0].content, /uncertainties/);
      assert.equal(output.code, diagram);
      assert.match(output.structure, /身份待确认/);
      assert.ok(output.warnings.some((item) => item.includes('箭头')));
      assert.ok(output.warnings.some((item) => item.includes('未经 LaTeX 编译')));
    }
    assert.equal(output.confidence, null);
  }
});

test('vision preserves text spaces and explicit commands but refuses truncation, refusal, prose and unbalanced TeX', async () => {
  const source = String.raw`\text{ a  b }+\mathrm{d}x+\alpha x+\,y\quad z`;
  assert.equal((await recognizeVision({ ...vision, ...mock(response(source)) })).code, source);
  for (const result of [response('x', 'length'), response('x', 'content_filter'),
    response('Here is your equation x=1'), response('this is not math'), response('\\frac{a}{'), response(''),
    response('\\begin{aligned}x\\end{matrix}'), response('```latex\nx\n```\nextra'),
    { choices: [{ finish_reason: 'stop', message: { refusal: SECRET_ECHO, content: 'x' } }] },
    { choices: [] }, { choices: [{ finish_reason: 'stop', message: { content: [{ text: 'x' }] } }] }
  ]) await assert.rejects(recognizeVision({ ...vision, ...mock(result) }), rejectsSafe('malformed'));
  await assert.rejects(recognizeVision({ ...vision, ...mock({ error: { message: SECRET_ECHO } }) }), rejectsSafe('rejected'));
  await assert.rejects(recognizeVision({ ...vision, ...mock(response(vision.apiKey)) }), rejectsSafe('malformed'));
  for (const patch of [{ mode: 'invalid' }, { apiKey: 'a\rb' }, { model: '' }, { png: Buffer.alloc(10_000_001) }]) {
    let sends = 0;
    await assert.rejects(recognizeVision({ ...vision, transport: () => { sends++; }, ...patch }));
    assert.equal(sends, 0);
  }
});

test('Feynman parser is independent and rejects missing topology fields, hidden document markers and file/shell macros', async () => {
  for (const content of [
    'x=y', diagramJSON(diagram, { structure: '' }), diagramJSON(diagram, { uncertainties: [true] }),
    diagramJSON(diagram.replace('\\end{document}', '%\\end{document}')),
    diagramJSON(diagram.replace('\\end{document}', '\\input{private}\\end{document}')),
    diagramJSON(diagram.replace('\\end{document}', '\\input2 \\end{document}')),
    diagramJSON(diagram.replace('\\end{document}', '\\write18{echo}\\end{document}')),
    diagramJSON(diagram.replace('\\end{document}', '\\directlua{evil()}\\end{document}')),
    diagramJSON(diagram.replace('\\end{document}', '\\csname input\\endcsname{private}\\end{document}')),
    diagramJSON(diagram.replace('\\end{document}', '\\def\\x{evil}\\end{document}')),
    diagramJSON(diagram.replace('\\end{document}', '^^5cinput{private}\\end{document}')),
    diagramJSON(diagram.replace('\\usepackage{tikz-feynman,amsmath}', '\\usepackage{tikz}\\usepackage [options]{shellesc}')),
    diagramJSON(diagram.replace('{standalone}', '{untrusted-class}')),
    diagramJSON(diagram.replace('\\end{document}', '\\usepackage\\name \\end{document}'))
  ]) await assert.rejects(recognizeVision({ ...vision, mode: 'feynman', ...mock(response(content)) }), rejectsSafe('malformed'));
  const fenced = `\`\`\`json\n${diagramJSON()}\n\`\`\``;
  assert.equal((await recognizeVision({ ...vision, mode: 'feynman', ...mock(response(fenced)) })).code, diagram);
  assert.equal(balanced(String.raw`\left\{x\right\}`), true);
  assert.equal(balanced('x% } ignored\n+y'), true);
  assert.equal(balanced('\\begin{aligned}x%\\end{aligned}'), false);
});

test('source formats wrap without rewriting internal LaTeX', () => {
  const source = String.raw`\begin{aligned}a&=\text{a  b}\\c&=d\end{aligned}`;
  assert.equal(formatSource(source, 'plain'), source);
  assert.equal(formatSource(source, 'inline'), `$${source}$`);
  assert.equal(formatSource(source, 'display'), `$$\n${source}\n$$`);
  assert.equal(formatSource(source, 'bracket'), `\\[\n${source}\n\\]`);
  assert.equal(formatSource(source, 'equation'), `\\begin{equation}\n${source}\n\\end{equation}`);
  assert.throws(() => formatSource(source, 'unknown'), rejectsSafe('configuration'));
});

test('usage query is read-only, UTC-scoped and grouped by repeated app_id and usage_type parameters', async () => {
  const probe = mock({ ocr_usage: [
    { app_id: credentials.appId, usage_type: 'image', count: 7 },
    { app_id: credentials.appId, usage_type: 'image-async', count: 3 },
    { app_id: 'other-app', usage_type: 'image', count: 99 },
    { app_id: credentials.appId, usage_type: 'pdf-pages', count: 123 }
  ] });
  const now = new Date('2026-12-31T23:59:59.000Z');
  const output = await fetchMathpixUsage({ ...credentials, now, ...probe });
  assert.deepEqual(output, { imageCount: 10, periodStart: '2026-12-01T00:00:00.000Z', periodEnd: '2027-01-01T00:00:00.000Z', fetchedAt: now.toISOString() });
  const request = probe.requests[0];
  const url = new URL(request.url);
  assert.equal(url.origin + url.pathname, 'https://api.mathpix.com/v3/ocr-usage');
  assert.equal(request.method, 'GET');
  assert.equal(request.body, undefined);
  assert.equal(request.timeoutMs, 15_000);
  assert.equal(request.headers.app_id, credentials.appId);
  assert.equal(request.headers.app_key, credentials.apiKey);
  assert.equal(url.searchParams.size, 7);
  assert.deepEqual(url.searchParams.getAll('group_by'), ['app_id', 'usage_type']);
  assert.equal(url.searchParams.get('timespan'), 'month');
  assert.equal(url.searchParams.get('page'), '1');
  assert.equal(url.searchParams.get('per_page'), '100');
  assert.equal(url.searchParams.get('from_date'), output.periodStart);
  assert.equal(url.searchParams.get('to_date'), output.periodEnd);
  assert.equal(url.searchParams.get('app_id'), null);
  assert.ok(!request.url.includes(credentials.apiKey));
  const feb = await fetchMathpixUsage({ ...credentials, now: new Date('2028-02-29T23:59:59Z'), ...mock({ ocr_usage: [] }) });
  assert.equal(feb.periodEnd, '2028-03-01T00:00:00.000Z');
  assert.equal(feb.imageCount, 0);
});

test('usage validates every count, handles overflow and refuses full pages instead of fabricating zero', async () => {
  const entry = { app_id: credentials.appId, usage_type: 'image', count: 1 };
  for (const value of [
    {}, { ocr_usage: null }, { ocr_usage: {} }, { ocr_usage: [{}] },
    ...[-1, true, '7', 1.5, Number.MAX_SAFE_INTEGER + 1, null].map((count) => ({ ocr_usage: [{ ...entry, count }] })),
    { ocr_usage: [{ ...entry, app_id: null }] }, { ocr_usage: [{ ...entry, usage_type: null }] },
    { ocr_usage: [{ ...entry, count: Number.MAX_SAFE_INTEGER }, { ...entry, count: 1 }] },
    { ocr_usage: [{ ...entry, app_id: 'other-app', usage_type: 'pdf-pages', count: -1 }] }
  ]) await assert.rejects(fetchMathpixUsage({ ...credentials, ...mock(value) }), rejectsSafe('malformed'));
  await assert.rejects(fetchMathpixUsage({ ...credentials, ...mock({ ocr_usage: Array.from({ length: 100 }, () => entry) }) }), rejectsSafe('incomplete'));
  await assert.rejects(fetchMathpixUsage({ ...credentials, ...mock({ error: SECRET_ECHO, ocr_usage: [] }) }), rejectsSafe('rejected'));
  await assert.rejects(fetchMathpixUsage({ ...credentials, now: new Date('invalid'), ...mock({ ocr_usage: [] }) }), rejectsSafe('configuration'));
});

// Node HTTPS stream doubles exercise the real transport without making a socket.
function requestDouble({ status = 200, chunks = ['{}'], headers = {}, error = false, hang = false, aborted = false } = {}) {
  const calls = [];
  function implementation(url, options, callback) {
    const request = new EventEmitter();
    request.destroy = () => { request.destroyed = true; };
    request.end = (body) => {
      calls.push({ url, options, body, request });
      setImmediate(() => {
        if (request.destroyed) return;
        if (error) { request.emit('error', Error(SECRET_ECHO)); return; }
        if (hang) return;
        const incoming = new EventEmitter();
        incoming.statusCode = status;
        incoming.headers = headers;
        incoming.destroy = () => { incoming.destroyed = true; };
        callback(incoming);
        if (incoming.destroyed) return;
        if (aborted) { incoming.emit('aborted'); return; }
        for (const chunk of chunks) { if (!incoming.destroyed) incoming.emit('data', Buffer.from(chunk)); }
        if (!incoming.destroyed) incoming.emit('end');
      });
    };
    return request;
  }
  return { transport: createJSONTransport(implementation), calls };
}
const tlsRequest = { url: 'https://api.example.test/v1', method: 'POST', headers: { Authorization: 'Bearer unit-test-fake-key' }, body: '{}' };

test('real transport enforces TLS, no redirects, bounded complete JSON and no retry or response error leakage', async () => {
  const probe = requestDouble({ chunks: ['{"ok":', 'true}'], headers: { 'content-length': '11' } });
  assert.deepEqual(await probe.transport(tlsRequest), { ok: true });
  assert.equal(probe.calls.length, 1);
  assert.equal(probe.calls[0].options.rejectUnauthorized, true);
  assert.equal(probe.calls[0].options.agent, false);
  assert.equal(probe.calls[0].body, '{}');
  for (const status of [301, 302, 307, 308, 401, 403, 429, 500]) {
    const failing = requestDouble({ status, chunks: [SECRET_ECHO], headers: { location: 'https://evil.example.test/' } });
    await assert.rejects(failing.transport(tlsRequest), rejectsSafe('http'));
    assert.equal(failing.calls.length, 1);
    assert.equal(failing.calls[0].request.destroyed, true);
  }
  for (const options of [
    { chunks: [SECRET_ECHO] }, { chunks: ['[]'] }, { chunks: ['null'] },
    { chunks: ['{}'], headers: { 'content-length': '3' } },
    { headers: { 'content-length': '2000001' } }, { headers: { 'content-length': 'x' } },
    { chunks: ['x'.repeat(2_000_001)] }, { headers: { 'content-encoding': 'gzip' } }
  ]) await assert.rejects(requestDouble(options).transport(tlsRequest), rejectsSafe('malformed'));
  await assert.rejects(requestDouble({ error: true }).transport(tlsRequest), rejectsSafe('network'));
  await assert.rejects(requestDouble({ aborted: true }).transport(tlsRequest), rejectsSafe('network'));
  await assert.rejects(probe.transport({ ...tlsRequest, url: 'http://api.example.test/' }), rejectsSafe('configuration'));
  await assert.rejects(probe.transport({ ...tlsRequest, url: 'https://user:pass@api.example.test/' }), rejectsSafe('configuration'));
});

test('transport has a hard deadline and immediate abort, including injected transports that ignore AbortSignal', async () => {
  const hanging = requestDouble({ hang: true });
  await assert.rejects(hanging.transport({ ...tlsRequest, timeoutMs: 10 }), rejectsSafe('network'));
  assert.equal(hanging.calls[0].request.destroyed, true);
  const controller = new AbortController();
  const active = requestDouble({ hang: true });
  const promise = active.transport({ ...tlsRequest, signal: controller.signal });
  controller.abort();
  await assert.rejects(promise, rejectsSafe('cancelled'));
  assert.equal(active.calls.length, 1);
  assert.equal(active.calls[0].request.destroyed, true);
  const alreadyCancelled = new AbortController(); alreadyCancelled.abort();
  const noSend = requestDouble();
  await assert.rejects(noSend.transport({ ...tlsRequest, signal: alreadyCancelled.signal }), rejectsSafe('cancelled'));
  assert.equal(noSend.calls.length, 0);
  await assert.rejects(sendJSON({ ...tlsRequest, timeoutMs: 10 }, () => new Promise(() => {})), rejectsSafe('network'));
  const outside = new AbortController();
  const bound = sendJSON({ ...tlsRequest, signal: outside.signal }, () => new Promise(() => {}));
  outside.abort();
  await assert.rejects(bound, rejectsSafe('cancelled'));
});
