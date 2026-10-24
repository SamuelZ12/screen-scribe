// All privileged work lives in the main process. This renderer accepts only the
// snapshot bridge and never reads files, uses credentials, or sends network calls.
const $ = (id) => document.getElementById(id);
const bridge = window.screenScribe;
const svgNS = 'http://www.w3.org/2000/svg';
const iconPaths = {
  capture: ['M8 3H5a2 2 0 0 0-2 2v3', 'M16 3h3a2 2 0 0 1 2 2v3', 'M21 16v3a2 2 0 0 1-2 2h-3', 'M8 21H5a2 2 0 0 1-2-2v-3'],
  import: ['M14 4H4a1 1 0 0 0-1 1v14a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7', 'M3 16l5-5 4 4 2-2 5 5', 'M17 3h5m-2.5-2.5v5', 'M7 7h.01'],
  paste: ['M9 5H5a2 2 0 0 0-2 2v13a1 1 0 0 0 1 1h12a2 2 0 0 0 2-2v-4', 'M9 3h12v12H9z', 'M9 12l3-3 3 3 2-2 4 4', 'M13 6h.01'],
  keyboard: ['M3 5h18v14H3z', 'M6 8h.01M10 8h.01M14 8h.01M18 8h.01M6 11h.01M10 11h.01M14 11h.01M18 11h.01M6 14h.01M18 14h.01M9 16h6'],
  list: ['M8 5h13M8 12h13M8 19h13M3 5h.01M3 12h.01M3 19h.01'],
  first: ['M5 4v16M19 5l-9 7 9 7z'],
  last: ['M19 4v16M5 5l9 7-9 7z'],
  left: ['M15 5l-7 7 7 7'],
  right: ['M9 5l7 7-7 7'],
  trash: ['M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7'],
  pin: ['M8 3h8M9 3v6l-4 5h14l-4-5V3M12 14v8'],
  settings: ['M9 3l-.5 3-2 1.2-2.8-1-2 3.4L4 11v2l-2.3 1.4 2 3.4 2.8-1 2 1.2.5 3h4l.5-3 2-1.2 2.8 1 2-3.4L18 13v-2l2.3-1.4-2-3.4-2.8 1-2-1.2-.5-3z', 'M14.5 12a3.5 3.5 0 1 1-7 0 3.5 3.5 0 0 1 7 0'],
  close: ['M6 6l12 12M18 6L6 18'],
  retry: ['M20 7a9 9 0 1 0 1 9', 'M20 2v6h-6'],
  copy: ['M9 3H6v18h14V7h-5', 'M9 2h6v5H9z', 'M4 6H2v16h14', 'M9 11h8M9 15h8'],
  edit: ['M11 4H4v17h17v-8', 'M10 14l1-4L20 1l3 3-9 9-4 1z'],
  photo: ['M3 4h18v16H3z', 'M3 16l5-5 5 5 3-3 5 5', 'M15 8h.01'],
  sliders: ['M3 5h10M17 5h4M3 12h3M10 12h11M3 19h12M19 19h2', 'M13 3h4v4h-4zM6 10h4v4H6zM15 17h4v4h-4z'],
  search: ['M15 15l7 7', 'M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0'],
  check: ['M4 12l5 5L21 5'],
};

function icon(name) {
  const svg = document.createElementNS(svgNS, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  for (const d of iconPaths[name] || iconPaths.photo) {
    const path = document.createElementNS(svgNS, 'path');
    path.setAttribute('d', d);
    svg.append(path);
  }
  return svg;
}
for (const element of document.querySelectorAll('[data-icon]')) element.append(icon(element.dataset.icon));

const copyFormats = [
  { id: 'plain', empty: 'LaTeX' },
  { id: 'inline', empty: '$ … $' },
  { id: 'display', empty: '$$ … $$' },
  { id: 'equation', empty: '\\begin{equation} … \\end{equation}' },
];
const rowElements = new Map();
for (const format of copyFormats) {
  const row = document.createElement('div');
  row.className = 'copy-row';
  const code = document.createElement('span');
  code.className = 'copy-code';
  row.append(code);
  for (const [action, iconName, label] of [
    [`copy-${format.id}`, 'copy', `复制 ${format.empty}`],
    ['edit-source', 'edit', '编辑源码'],
    ['zoom-preview', 'search', '放大公式预览'],
  ]) {
    const button = document.createElement('button');
    button.className = 'row-button';
    button.dataset.action = action;
    button.title = label;
    button.setAttribute('aria-label', label);
    button.append(icon(iconName));
    row.append(button);
  }
  $('copy-rows').append(row);
  rowElements.set(format.id, { row, code });
}

let state = {
  version: '', platform: '', isDemo: false,
  settings: { provider: 'mathpix', mode: 'equation', captureShortcut: 'Control+Shift+L', pasteShortcut: 'Control+Shift+V', visionBaseURL: '', visionModel: '', monthlyImageLimit: 0, persistImages: false },
  credentialStatus: { mathpix: false, vision: false },
  busy: false, error: '', notice: '', result: null, history: [], quota: {}, pinned: false, shortcutError: '',
};
let page = 'ocr';
let showOriginal = false;
let zoomed = false;
let draftId = null;
let draftCode = '';
let lastServerCode = '';
let dirty = false;
let toastTimer;
let copiedTimer;
let copiedFormat = null;
let previewCache = '';
let historyCache = '';
let confirmationCallback = null;
let previousFocus = null;
let inFlight = 0;
let pendingCredentialSave = false;
let lastStateError = '';

function asString(value) { return typeof value === 'string' ? value : ''; }
function currentCode() { return draftCode; }
function currentMode() { return state.result?.mode || state.settings.mode; }
function validImage(value) { return typeof value === 'string' && /^data:image\/(?:png|jpe?g|webp);base64,[A-Za-z0-9+/=\r\n]+$/i.test(value); }
function numberLabel(value) { return Number.isFinite(value) && value >= 0 ? Math.floor(value).toLocaleString('en-US') : '—'; }
function isBusy() { return Boolean(state.busy); }

function toast(message) {
  clearTimeout(toastTimer);
  $('toast').textContent = message;
  $('toast').hidden = false;
  toastTimer = setTimeout(() => { $('toast').hidden = true; }, 2800);
}

function feedback(message, error = false) {
  $('settings-feedback').textContent = message;
  $('settings-feedback').classList.toggle('error', error);
  $('settings-feedback').hidden = !message;
}

async function invoke(name, payload = {}, { success, settings = false } = {}) {
  if (!bridge) { toast('应用连接尚未就绪，请从 ScreenScribe 程序打开。'); return false; }
  inFlight += 1;
  try {
    const response = await bridge.action(name, payload);
    if (!response?.ok) {
      const message = asString(response?.error) || '操作未完成，请重试。';
      if (settings || page === 'settings') feedback(message, true);
      else toast(message);
      return false;
    }
    applyState(await bridge.getState());
    if (success) { if (settings || page === 'settings') feedback(success); else toast(success); }
    return true;
  } catch {
    const message = '无法连接本机应用服务，请稍后重试。';
    if (settings || page === 'settings') feedback(message, true); else toast(message);
    return false;
  } finally {
    inFlight -= 1;
  }
}

function applyState(snapshot) {
  if (!snapshot || typeof snapshot !== 'object') return;
  const previous = state;
  state = {
    ...state, ...snapshot,
    settings: { ...state.settings, ...(snapshot.settings || {}) },
    credentialStatus: { ...state.credentialStatus, ...(snapshot.credentialStatus || {}) },
    quota: snapshot.quota || {},
    history: Array.isArray(snapshot.history) ? snapshot.history : [],
  };
  const id = state.result?.id || null;
  const code = asString(state.result?.code);
  if (id !== draftId || (!dirty && code !== lastServerCode)) {
    draftId = id;
    draftCode = code;
    dirty = false;
    $('source-editor').value = code;
  }
  lastServerCode = code;
  if (state.error && state.error !== lastStateError) {
    if (page !== 'settings' && page !== 'history') page = 'data';
    else if (page === 'settings') feedback(asString(state.error), true);
  }
  lastStateError = asString(state.error);
  if (previous.settings.provider !== state.settings.provider && page === 'settings') populateSettings(false);
  render();
}

function setPage(next, { focus = false, section } = {}) {
  page = next;
  $('mode-menu').hidden = true;
  $('mode-button').setAttribute('aria-expanded', 'false');
  if (next === 'settings') { populateSettings(); feedback(''); }
  render();
  if (section) {
    requestAnimationFrame(() => {
      $(section)?.scrollIntoView({ block: 'start', behavior: 'smooth' });
      if (section === 'quota-section') $('billing-details').open = true;
    });
  }
  if (focus && next === 'data') requestAnimationFrame(() => $('source-editor').focus());
}

function render() {
  const busy = isBusy();
  const result = state.result;
  const code = currentCode();
  const hasCode = Boolean(code.trim());
  const hasImage = validImage(result?.imageDataUrl);
  const secondary = page === 'settings' || page === 'history';
  $('recognition-page').hidden = secondary;
  $('settings-page').hidden = page !== 'settings';
  $('history-page').hidden = page !== 'history';
  $('settings-button').classList.toggle('active', page === 'settings');
  $('history-button').classList.toggle('active', page === 'history');
  $('pin-button').classList.toggle('active', Boolean(state.pinned));
  $('pin-button').setAttribute('aria-pressed', String(Boolean(state.pinned)));
  $('pin-button').title = state.pinned ? '取消固定面板' : '固定面板';
  $('pin-button').setAttribute('aria-label', $('pin-button').title);

  const historyIndex = state.history.findIndex((entry) => entry.id === result?.id);
  $('history-counter').textContent = `${historyIndex < 0 ? 0 : state.history.length - historyIndex}/${state.history.length}`;
  $('first-button').disabled = busy || !state.history.length || historyIndex === state.history.length - 1;
  $('prev-button').disabled = busy || !state.history.length || historyIndex >= state.history.length - 1;
  $('next-button').disabled = busy || !state.history.length || historyIndex <= 0;
  $('last-button').disabled = busy || !state.history.length || historyIndex === 0;
  $('delete-button').disabled = busy || !result?.id;
  for (const name of ['capture', 'import-image', 'paste-image']) {
    for (const button of document.querySelectorAll(`[data-action="${name}"]`)) button.disabled = busy;
  }
  $('mode-button').disabled = busy;
  $('mode-label').textContent = state.settings.mode === 'feynman' ? 'Feynman · 实验性' : 'Equation';
  $('provider-label').textContent = state.isDemo ? '离线演示' : state.settings.provider === 'vision' ? 'Vision' : 'Mathpix';
  $('mathpix-choice').textContent = state.settings.provider === 'mathpix' ? '✓' : '';
  $('vision-choice').textContent = state.settings.provider === 'vision' ? '✓' : '';
  $('capture-hint').textContent = asString(state.settings.captureShortcut).replace('Control', 'Ctrl').replace('CommandOrControl', 'Ctrl');
  const captureTitle = `直接框选截图 · ${state.settings.captureShortcut || 'Ctrl+Shift+L'}`;
  const captureButton = document.querySelector('.toolbar [data-action="capture"]');
  captureButton.title = captureTitle;
  captureButton.setAttribute('aria-label', captureTitle);

  for (const tab of ['ocr', 'data', 'original']) {
    $(`tab-${tab}`).classList.toggle('selected', page === tab);
    $(`tab-${tab}`).setAttribute('aria-selected', String(page === tab));
    $(`tab-${tab}`).tabIndex = page === tab ? 0 : -1;
  }
  $('result-area').setAttribute('aria-labelledby', `tab-${['ocr', 'data', 'original'].includes(page) ? page : 'ocr'}`);
  $('data-content').hidden = page !== 'data';
  $('preview-header').hidden = page === 'data';
  $('preview-content').hidden = page === 'data';
  $('show-original').disabled = !hasImage;
  $('show-original').firstChild.textContent = showOriginal || page === 'original' ? 'Hide Original ' : 'Show Original ';
  $('retry-button').disabled = busy || !hasImage;
  $('busy-spinner').hidden = !busy;
  $('cancel-button').hidden = !busy;
  $('preview-notice').textContent = busy ? '正在识别…' : asString(state.notice);
  $('source-editor').disabled = busy;
  $('save-source').disabled = busy || !result?.id || !dirty;
  $('edit-state').textContent = dirty ? '有未保存修改' : '';
  $('source-heading').textContent = currentMode() === 'feynman' ? 'TikZ 源码' : 'LaTeX 源码';
  $('error-message').hidden = !state.error;
  $('error-message').textContent = asString(state.error);
  renderWarnings(result?.warnings);
  $('copy-label').textContent = currentMode() === 'feynman' ? 'Copy TikZ' : 'Copy LaTeX';
  $('copy-source-button').disabled = !hasCode || busy;
  $('edit-button').disabled = !hasCode || busy;
  $('copy-png-button').disabled = !hasImage;
  $('original-button').disabled = !hasImage;
  for (const format of copyFormats) {
    const entry = rowElements.get(format.id);
    entry.code.textContent = hasCode ? previewSource(code, format.id).replace(/\s*\n\s*/g, ' ') : format.empty;
    entry.code.title = hasCode ? previewSource(code, format.id) : format.empty;
    for (const button of entry.row.querySelectorAll('button')) button.disabled = !hasCode || busy;
    const copyButton = entry.row.querySelector('button');
    const copied = copiedFormat === format.id;
    if (copyButton.dataset.copied !== String(copied)) {
      copyButton.replaceChildren(icon(copied ? 'check' : 'copy'));
      copyButton.classList.toggle('copied', copied);
      copyButton.dataset.copied = String(copied);
    }
  }

  const confidence = typeof result?.confidence === 'number' && Number.isFinite(result.confidence) ? Math.max(0, Math.min(1, result.confidence)) : null;
  $('confidence-label').textContent = confidence === null ? 'Confidence · 未提供' : `Confidence · ${Math.round(confidence * 100)}%`;
  $('confidence-fill').style.width = `${confidence === null ? 0 : confidence * 100}%`;
  if (confidence === null) $('confidence-bar').removeAttribute('aria-valuenow');
  else $('confidence-bar').setAttribute('aria-valuenow', String(Math.round(confidence * 100)));
  $('footer-status').classList.toggle('error', Boolean(state.error));
  $('footer-status').textContent = copiedFormat ? '已复制 ✓' : state.error ? '查看错误' : result?.warnings?.length ? `${result.warnings.length} 项核查提示` : '仅处理所选区域 · 本地历史';
  renderPreview(code, hasImage);
  renderQuota();
  if (page === 'settings') renderSettingsStatus();
  if (page === 'history') renderHistory();
}

function previewSource(code, format) {
  if (currentMode() === 'feynman') return code;
  if (format === 'inline') return `$${code}$`;
  if (format === 'display') return `$$${code}$$`;
  if (format === 'equation') return `\\begin{equation}${code}\\end{equation}`;
  return code;
}

function renderWarnings(warnings) {
  const list = $('warnings-list');
  const safe = Array.isArray(warnings) ? warnings.filter((v) => typeof v === 'string') : [];
  list.hidden = !safe.length;
  list.replaceChildren(...safe.map((warning) => { const item = document.createElement('li'); item.textContent = warning; return item; }));
}

function renderPreview(code, hasImage) {
  const wantsOriginal = page === 'original' || showOriginal;
  const feynman = currentMode() === 'feynman';
  $('original-image').hidden = !wantsOriginal || !hasImage;
  if (wantsOriginal && hasImage && $('original-image').getAttribute('src') !== state.result.imageDataUrl) $('original-image').src = state.result.imageDataUrl;
  if (!hasImage) $('original-image').removeAttribute('src');
  $('math-preview').hidden = wantsOriginal || !code || feynman;
  $('structure-preview').hidden = wantsOriginal || !code || !feynman;
  $('empty-state').hidden = wantsOriginal ? hasImage : Boolean(code);
  if (wantsOriginal && !hasImage) {
    $('empty-title').textContent = '此记录没有保存原图';
    $('empty-subtitle').textContent = '可在设置中开启历史原图保存';
    $('empty-state').querySelector('button').hidden = true;
  } else {
    $('empty-title').textContent = state.error ? '这次识别未完成' : '框选一下，让公式变成 LaTeX';
    $('empty-subtitle').textContent = state.error ? '在 Data 中查看错误，或重新框选清晰的公式' : '拖选屏幕上的公式，或导入一张图片';
    $('empty-state').querySelector('button').hidden = false;
  }
  if (feynman) $('structure-text').textContent = asString(state.result?.structure) || '模型未返回图结构。请在 Data 中核查 TikZ 源码。';
  $('math-preview').classList.toggle('zoomed', zoomed);
  const cache = `${currentMode()}\0${code}`;
  if (cache === previewCache) return;
  previewCache = cache;
  if (!code || feynman) { $('math-preview').replaceChildren(); return; }
  try {
    if (!window.katex?.render) throw new Error('local renderer unavailable');
    window.katex.render(code, $('math-preview'), {
      displayMode: true, throwOnError: false, trust: false,
      strict: 'warn', maxExpand: 1000, maxSize: 20,
      output: 'htmlAndMathml', errorColor: '#bb565c',
    });
  } catch {
    // A failed preview stays plain text. Generated code is never HTML or JS.
    $('math-preview').textContent = code;
  }
}

function renderQuota() {
  const quota = state.quota || {};
  const available = Number.isFinite(quota.remaining) && quota.remaining >= 0;
  const monthly = Number.isFinite(quota.monthlyUsed) && quota.monthlyUsed >= 0;
  $('quota-badge').hidden = state.settings.provider !== 'mathpix';
  $('quota-badge').textContent = available ? `总剩余约 ${numberLabel(quota.remaining)} 次${monthly ? ` · 本月已用 ${numberLabel(quota.monthlyUsed)}` : ''}` : monthly ? `本月已用 ${numberLabel(quota.monthlyUsed)} 次` : '设置额度';
  $('quota-badge').classList.toggle('stale', Boolean(quota.stale));
  const detail = asString(quota.detail);
  $('quota-badge').title = detail || '填写 Billing 快照，查看保守剩余额度估算';
  $('quota-badge').setAttribute('aria-label', `${$('quota-badge').textContent}，查看额度设置`);
  $('settings-remaining').textContent = available ? `约 ${numberLabel(quota.remaining)} 次` : '尚未设置';
  $('settings-monthly').textContent = monthly ? `${numberLabel(quota.monthlyUsed)} 次` : '—';
  $('settings-monthly-remaining').textContent = Number.isFinite(quota.monthlyRemaining) && quota.monthlyRemaining >= 0 ? `${numberLabel(quota.monthlyRemaining)} 次` : '未设置上限';
  const time = quota.fetchedAt ? formatTime(quota.fetchedAt) : '尚未查询';
  const next = Number.isInteger(quota.nextRefreshIn) ? quota.nextRefreshIn : 5;
  $('quota-detail').textContent = `${detail || '总剩余按账单快照保守估算，不是官方实时余额。'}\n用量查询：${time} · 再完成 ${next} 次后自动校准${quota.stale ? ' · 快照待更新' : ''}`;
}

function populateSettings(includeValues = true) {
  $('provider-select').value = state.settings.provider;
  $('mode-select').value = state.settings.mode;
  if (includeValues) {
    $('vision-base').value = asString(state.settings.visionBaseURL);
    $('vision-model').value = asString(state.settings.visionModel);
    $('capture-shortcut').value = asString(state.settings.captureShortcut);
    $('paste-shortcut').value = asString(state.settings.pasteShortcut);
    $('persist-images').checked = Boolean(state.settings.persistImages);
    $('monthly-limit').value = state.settings.monthlyImageLimit || '';
    if (!$('billing-observed').value) $('billing-observed').value = localDateTime();
  }
  renderSettingsStatus();
}

function renderSettingsStatus() {
  const provider = state.settings.provider;
  const saved = Boolean(state.credentialStatus[provider]);
  $('mathpix-fields').hidden = provider !== 'mathpix';
  $('vision-fields').hidden = provider !== 'vision';
  $('credential-status').textContent = saved ? '凭据已加密保存' : '未保存凭据';
  $('credential-status').classList.toggle('saved', saved);
  $('delete-credentials').disabled = !saved || isBusy();
  $('test-connection').disabled = !saved || isBusy();
  $('api-key').disabled = pendingCredentialSave;
  $('mathpix-app-id').disabled = pendingCredentialSave;
  $('credentials-form').querySelector('[type="submit"]').disabled = pendingCredentialSave || isBusy();
  $('provider-select').disabled = isBusy() || pendingCredentialSave;
  $('mode-select').disabled = isBusy();
  $('version-label').textContent = state.version ? `V${state.version}` : '';
  $('shortcut-error').hidden = !state.shortcutError;
  $('shortcut-error').textContent = asString(state.shortcutError);
  $('mode-explanation').textContent = state.settings.mode === 'feynman' ? '费曼图识别为实验性功能，需要支持图片的视觉模型；输出只作源码，不自动执行。' : 'Mathpix 适用于公式识别，也可使用兼容 OpenAI 的视觉模型。';
  for (const button of document.querySelectorAll('[data-action="refresh-usage"]')) button.disabled = !state.credentialStatus.mathpix || isBusy();
}

function formatTime(value) {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return '时间未知';
  return date.toLocaleString('zh-CN', { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false });
}

function localDateTime() {
  const date = new Date();
  return new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
}

function renderHistory() {
  $('history-total').textContent = `${state.history.length} 条`;
  for (const name of ['remove-history-images', 'clear-history']) document.querySelector(`[data-action="${name}"]`).disabled = !state.history.length || isBusy();
  const cache = JSON.stringify([state.result?.id, isBusy(), state.history.map((entry) => [entry.id, entry.createdAt, entry.code, entry.provider, entry.mode, entry.imageDataUrl?.length])]);
  if (historyCache === cache) return;
  historyCache = cache;
  $('history-list').replaceChildren();
  if (!state.history.length) {
    const empty = document.createElement('div');
    empty.className = 'history-empty';
    empty.append(icon('list'));
    const title = document.createElement('span'); title.textContent = '还没有识别记录'; empty.append(title);
    const detail = document.createElement('span'); detail.textContent = '完成一次识别后，源码会自动保存在这里'; detail.className = 'muted'; empty.append(detail);
    $('history-list').append(empty);
    return;
  }
  for (const entry of state.history) {
    const row = document.createElement('div');
    row.className = 'history-entry';
    row.classList.toggle('selected', entry.id === state.result?.id);
    if (validImage(entry.imageDataUrl)) {
      const image = document.createElement('img'); image.src = entry.imageDataUrl; image.alt = '历史截图缩略图'; row.append(image);
    } else {
      const thumb = document.createElement('span'); thumb.className = 'history-thumbnail'; thumb.append(icon('photo')); row.append(thumb);
    }
    const content = document.createElement('button');
    content.className = 'history-entry-content';
    content.dataset.action = 'select-history'; content.dataset.id = entry.id;
    content.disabled = isBusy();
    content.title = `打开 ${formatTime(entry.createdAt)} 的识别记录`;
    content.setAttribute('aria-label', content.title);
    const code = document.createElement('span'); code.className = 'history-code'; code.textContent = asString(entry.code).replace(/\s*\n\s*/g, ' ') || '空源码';
    const meta = document.createElement('span'); meta.className = 'history-meta'; meta.textContent = `${formatTime(entry.createdAt)} · ${entry.provider === 'mathpix' ? 'Mathpix' : 'Vision'} · ${entry.mode === 'feynman' ? 'TikZ' : 'LaTeX'}${entry.id === state.result?.id ? ' · 当前' : ''}`;
    content.append(code, meta); row.append(content);
    const remove = document.createElement('button'); remove.className = 'icon-button'; remove.dataset.action = 'delete-history'; remove.dataset.id = entry.id; remove.title = '删除这条历史记录'; remove.setAttribute('aria-label', remove.title); remove.disabled = isBusy(); remove.append(icon('trash')); row.append(remove);
    $('history-list').append(row);
  }
}

async function saveDraft() {
  if (!dirty) return true;
  if (!state.result?.id || isBusy()) return false;
  const submitted = draftCode;
  const ok = await invoke('save-source', { code: submitted });
  if (ok && draftCode === submitted) { dirty = false; lastServerCode = submitted; render(); }
  return ok;
}

async function copySource(format) {
  if (!(await saveDraft())) return;
  const actualFormat = currentMode() === 'feynman' ? 'plain' : format;
  if (await invoke('copy-source', { format: actualFormat })) {
    copiedFormat = format;
    clearTimeout(copiedTimer);
    render();
    copiedTimer = setTimeout(() => { copiedFormat = null; render(); }, 2000);
  }
}

function confirmAction(title, detail, callback, label = '确认') {
  previousFocus = document.activeElement;
  confirmationCallback = callback;
  $('confirmation-title').textContent = title;
  $('confirmation-detail').textContent = detail;
  $('confirm-button').textContent = label;
  $('confirm-button').setAttribute('aria-label', label);
  $('confirmation').hidden = false;
  $('confirmation').querySelector('[data-action="dismiss-confirmation"]').focus();
}

function dismissConfirmation() {
  $('confirmation').hidden = true;
  confirmationCallback = null;
  if (previousFocus?.isConnected) previousFocus.focus();
}

function withCleanDraft(callback) {
  if (!dirty) { callback(); return; }
  confirmAction('离开未保存的源码？', '未保存的修改会被丢弃。你也可以取消，先在 Data 中保存修改。', () => {
    dirty = false;
    draftCode = asString(state.result?.code);
    $('source-editor').value = draftCode;
    callback();
  }, '丢弃修改并继续');
}

async function selectHistory(id) {
  if (!id) return;
  if (await invoke('select-history', { id })) { showOriginal = false; zoomed = false; setPage('ocr'); }
}

async function changeProvider(provider) {
  if (provider === state.settings.provider) return;
  $('api-key').value = '';
  $('mathpix-app-id').value = '';
  const patch = { provider };
  if (provider === 'mathpix' && state.settings.mode === 'feynman') patch.mode = 'equation';
  if (await invoke('update-settings', patch)) { populateSettings(false); render(); }
}

async function changeMode(mode) {
  const patch = { mode };
  if (mode === 'feynman') patch.provider = 'vision';
  if (await invoke('update-settings', patch)) { populateSettings(false); render(); }
}

const actions = {
  capture: () => withCleanDraft(() => { showOriginal = false; setPage('ocr'); return invoke('capture'); }),
  'import-image': () => withCleanDraft(() => { showOriginal = false; setPage('ocr'); return invoke('import-image'); }),
  'paste-image': () => withCleanDraft(() => { showOriginal = false; setPage('ocr'); return invoke('paste-image'); }),
  recognize: () => withCleanDraft(() => invoke('recognize')),
  cancel: () => invoke('cancel'),
  hide: () => invoke('hide'),
  quit: () => invoke('quit'),
  settings: () => setPage(page === 'settings' ? 'ocr' : 'settings'),
  shortcuts: () => setPage('settings', { section: 'shortcuts-section' }),
  'quota-settings': () => setPage('settings', { section: 'quota-section' }),
  history: () => setPage(page === 'history' ? 'ocr' : 'history'),
  back: () => setPage('ocr'),
  'tab-ocr': () => { showOriginal = false; setPage('ocr'); },
  'tab-data': () => setPage('data'),
  'tab-original': () => setPage('original'),
  'edit-source': () => setPage('data', { focus: true }),
  'toggle-original': () => {
    if (page === 'original') { showOriginal = false; setPage('ocr'); }
    else { showOriginal = !showOriginal; render(); }
  },
  'zoom-preview': () => { zoomed = !zoomed; showOriginal = false; setPage('ocr'); },
  'save-source': () => saveDraft().then((ok) => { if (ok) toast('修改已保存'); }),
  'copy-plain': () => copySource('plain'),
  'copy-inline': () => copySource('inline'),
  'copy-display': () => copySource('display'),
  'copy-equation': () => copySource('equation'),
  'copy-png': () => invoke('copy-png', {}, { success: '原图已复制' }),
  'toggle-pin': () => invoke('set-pinned', { value: !state.pinned }),
  'toggle-mode-menu': () => { const hidden = !$('mode-menu').hidden; $('mode-menu').hidden = hidden; $('mode-button').setAttribute('aria-expanded', String(!hidden)); },
  'mode-equation': () => { $('mode-menu').hidden = true; return changeMode('equation'); },
  'mode-feynman': () => { $('mode-menu').hidden = true; return changeMode('feynman'); },
  'provider-mathpix': () => { $('mode-menu').hidden = true; return changeProvider('mathpix'); },
  'provider-vision': () => { $('mode-menu').hidden = true; return changeProvider('vision'); },
  'first-history': () => withCleanDraft(() => selectHistory(state.history.at(-1)?.id)),
  'last-history': () => withCleanDraft(() => selectHistory(state.history[0]?.id)),
  'prev-history': () => withCleanDraft(() => {
    const index = state.history.findIndex((item) => item.id === state.result?.id);
    return selectHistory(state.history[Math.min(state.history.length - 1, index + 1)]?.id);
  }),
  'next-history': () => withCleanDraft(() => {
    const index = state.history.findIndex((item) => item.id === state.result?.id);
    return selectHistory(state.history[Math.max(0, index - 1)]?.id);
  }),
  'select-history': (button) => withCleanDraft(() => selectHistory(button.dataset.id)),
  'delete-current': () => {
    if (!state.result?.id) return;
    const id = state.result.id;
    confirmAction('删除当前记录？', '这条记录的源码和已保存原图将从本机历史中移除。', () => invoke('delete-history', { id }), '删除记录');
  },
  'delete-history': (button) => confirmAction('删除这条记录？', '这条记录的源码和已保存原图将从本机历史中移除。', () => invoke('delete-history', { id: button.dataset.id }), '删除记录'),
  'clear-history': () => confirmAction('清空全部历史？', '将删除本机的全部识别记录和历史原图。此操作不可撤销。', () => invoke('clear-history'), '清空历史'),
  'remove-history-images': () => confirmAction('移除历史原图？', '保留识别源码，只删除本机历史记录保存的图片。', () => invoke('remove-history-images'), '移除原图'),
  'delete-credentials': () => confirmAction('删除已保存凭据？', '这只删除本机保存的当前服务凭据，不会注销或撤销服务端的 API Key。', () => invoke('delete-credentials', { provider: state.settings.provider, baseURL: state.settings.visionBaseURL }, { success: '凭据已删除', settings: true }), '删除凭据'),
  'test-connection': () => invoke('test-connection', {}, { success: '连接测试已完成', settings: true }),
  'refresh-usage': () => invoke('refresh-usage', {}, { success: '官方用量已更新', settings: true }),
  'save-vision-settings': () => {
    const baseURL = $('vision-base').value.trim();
    const model = $('vision-model').value.trim();
    if (!baseURL || !model) { feedback('请填写 HTTPS API 地址和支持图片输入的模型名称。', true); return; }
    return invoke('update-settings', { visionBaseURL: baseURL, visionModel: model }, { success: 'API 地址和模型名称已保存', settings: true });
  },
  'clear-billing': () => confirmAction('清除余额快照？', '清除后不再显示总剩余估算，本月用量和扫描计数会保留。', () => invoke('clear-billing', {}, { success: '余额快照已清除', settings: true }), '清除快照'),
  'save-monthly-limit': () => {
    const value = $('monthly-limit').value.trim();
    if (!/^\d*$/.test(value) || !Number.isSafeInteger(Number(value)) || Number(value) > 1000000000) { feedback('请填写 0 到 1,000,000,000 之间的整数；0 表示不设置上限。', true); return; }
    return invoke('update-settings', { monthlyImageLimit: Number(value || 0) }, { success: '图片月上限已保存', settings: true });
  },
  'open-data-folder': () => invoke('open-data-folder'),
  'open-help': () => invoke('open-help'),
  'footer-detail': () => { if (state.error || state.result?.warnings?.length) setPage('data'); },
  'dismiss-confirmation': dismissConfirmation,
  confirm: () => { const callback = confirmationCallback; dismissConfirmation(); callback?.(); },
};

document.addEventListener('click', (event) => {
  const button = event.target.closest('button[data-action]');
  if (button && !button.disabled) {
    const handler = actions[button.dataset.action];
    if (handler) Promise.resolve().then(() => handler(button)).catch(() => toast('操作未完成，请重试。'));
  }
  if (!$('mode-menu').hidden && !event.target.closest('#mode-menu, #mode-button')) {
    $('mode-menu').hidden = true;
    $('mode-button').setAttribute('aria-expanded', 'false');
  }
});

$('source-editor').addEventListener('input', () => {
  draftCode = $('source-editor').value;
  dirty = draftCode !== asString(state.result?.code);
  copiedFormat = null;
  render();
});

$('provider-select').addEventListener('change', () => { changeProvider($('provider-select').value).catch(() => feedback('保存服务设置失败。', true)); });
$('mode-select').addEventListener('change', () => { changeMode($('mode-select').value).catch(() => feedback('保存类型设置失败。', true)); });

$('credentials-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  if (pendingCredentialSave || isBusy()) return;
  const provider = state.settings.provider;
  const apiKey = $('api-key').value.trim();
  const appId = $('mathpix-app-id').value.trim();
  const baseURL = $('vision-base').value.trim();
  const model = $('vision-model').value.trim();
  if (!apiKey || (provider === 'mathpix' && !appId)) { feedback('请填写完整的 App ID 和 API Key；视觉服务只需 API Key。', true); return; }
  if (provider === 'vision' && (!baseURL || !model)) { feedback('请填写 HTTPS API 地址和支持图片输入的模型名称。', true); return; }
  pendingCredentialSave = true; renderSettingsStatus();
  try {
    if (provider === 'vision' && !(await invoke('update-settings', { visionBaseURL: baseURL, visionModel: model }, { settings: true }))) return;
    const ok = await invoke('save-credentials', { provider, appId: provider === 'mathpix' ? appId : undefined, apiKey, baseURL: provider === 'vision' ? baseURL : undefined }, { success: '凭据已加密保存', settings: true });
    if (ok) { $('api-key').value = ''; $('mathpix-app-id').value = ''; }
  } finally { pendingCredentialSave = false; renderSettingsStatus(); }
});

$('preferences-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  await invoke('update-settings', {
    captureShortcut: $('capture-shortcut').value.trim(),
    pasteShortcut: $('paste-shortcut').value.trim(),
    persistImages: $('persist-images').checked,
  }, { success: '快捷键和历史设置已保存', settings: true });
});

$('billing-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const creditUSD = $('billing-credit').value.trim();
  const pendingUSD = $('billing-pending').value.trim();
  const imagePriceUSD = $('billing-price').value.trim();
  const observed = new Date($('billing-observed').value);
  const validMoney = [creditUSD, pendingUSD].every((value) => /^\d+(?:\.\d{1,2})?$/.test(value));
  const validPrice = /^\d+(?:\.\d{1,6})?$/.test(imagePriceUSD) && Number(imagePriceUSD) > 0;
  if (!validMoney || !validPrice || !Number.isFinite(observed.getTime())) {
    feedback('余额和待结算用量须为非负美元金额，最多 2 位小数；图片单价须大于 0，最多 6 位小数。请同时填写有效快照时间。', true); return;
  }
  const ok = await invoke('save-billing', { creditUSD, pendingUSD, imagePriceUSD, observedAt: observed.toISOString() }, { success: '余额快照已保存，后续逐张扣减并每 5 次校准', settings: true });
  if (ok) {
    for (const id of ['billing-credit', 'billing-pending', 'billing-price']) $(id).value = '';
    $('billing-details').open = false;
  }
});

document.addEventListener('keydown', (event) => {
  if (!$('confirmation').hidden) {
    if (event.key === 'Escape') { event.preventDefault(); dismissConfirmation(); }
    if (event.key === 'Tab') {
      const buttons = [...$('confirmation').querySelectorAll('button')];
      const index = buttons.indexOf(document.activeElement);
      if ((event.shiftKey && index === 0) || (!event.shiftKey && index === buttons.length - 1)) { event.preventDefault(); buttons[event.shiftKey ? buttons.length - 1 : 0].focus(); }
    }
    return;
  }
  if (event.key === 'Escape') {
    event.preventDefault();
    if (!$('mode-menu').hidden) { $('mode-menu').hidden = true; $('mode-button').setAttribute('aria-expanded', 'false'); $('mode-button').focus(); }
    else if (isBusy()) invoke('cancel');
    else if (page === 'settings' || page === 'history') setPage('ocr');
    else invoke('hide');
  }
  if ((event.ctrlKey || event.metaKey) && event.key === ',') { event.preventDefault(); setPage('settings'); }
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's' && page === 'data') { event.preventDefault(); saveDraft(); }
  if (event.target.matches('[role="tab"]') && ['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) {
    event.preventDefault();
    const pages = ['ocr', 'data', 'original'];
    const index = pages.indexOf(page);
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? 2 : (index + (event.key === 'ArrowRight' ? 1 : 2)) % 3;
    setPage(pages[next]); $(`tab-${pages[next]}`).focus();
  }
});

window.addEventListener('pagehide', () => {
  // Password fields are not a local credential store.
  $('api-key').value = '';
  $('mathpix-app-id').value = '';
});

render();
if (bridge) {
  bridge.onState(applyState);
  bridge.getState().then(applyState).catch(() => { toast('无法读取应用状态，请重新打开面板。'); });
} else {
  $('preview-notice').textContent = '应用连接未就绪';
}
