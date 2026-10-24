'use strict';

const { fail, isObject } = require('./transport.cjs');
const MAX_CODE = 200_000;

function unwrap(source) {
  if (typeof source !== 'string' || source.length > MAX_CODE) throw fail('malformed');
  let value = source.trim();
  const fence = value.match(/^```(?:latex|tex|math)?\s*\n([\s\S]*)\n?```$/i);
  if (fence) value = fence[1].trim();
  for (const [open, close] of [['\\[', '\\]'], ['\\(', '\\)'], ['$$', '$$'], ['$', '$']]) {
    if (value.startsWith(open) && value.endsWith(close) && value.length >= open.length + close.length) {
      return value.slice(open.length, -close.length).trim();
    }
  }
  return value;
}

function formatSource(code, format) {
  if (typeof code !== 'string' || code.length > MAX_CODE) throw fail('malformed');
  switch (format) {
    case 'plain': return code;
    case 'inline': return `$${code}$`;
    case 'display': return `$$\n${code}\n$$`;
    case 'equation': return `\\begin{equation}\n${code}\n\\end{equation}`;
    case 'bracket': return `\\[\n${code}\n\\]`;
    default: throw fail('configuration');
  }
}

// Remove TeX comments while preserving escaped percent signs and escaped
// backslashes. This prevents commented-out closing braces/environments from
// incorrectly satisfying validation.
function withoutComments(code) {
  let result = '';
  for (let i = 0; i < code.length; i++) {
    if (code[i] === '\\' && i + 1 < code.length && /[{}%\\]/.test(code[i + 1])) {
      result += code[i] + code[++i];
    } else if (code[i] === '%') {
      while (i < code.length && code[i] !== '\n') i++;
      result += '\n';
    } else result += code[i];
  }
  return result;
}

function balanced(code) {
  const value = withoutComments(code);
  let depth = 0;
  for (let i = 0; i < value.length; i++) {
    if (value[i] === '\\' && i + 1 < value.length && /[{}%\\]/.test(value[i + 1])) { i++; continue; }
    if (value[i] === '{') depth++;
    if (value[i] === '}' && --depth < 0) return false;
  }
  if (depth !== 0) return false;
  const stack = [];
  for (const match of value.matchAll(/(?<!\\)\\(begin|end)\s*\{([^}]+)\}/g)) {
    if (match[1] === 'begin') stack.push(match[2]);
    else if (stack.pop() !== match[2]) return false;
  }
  return stack.length === 0;
}

function parseEquation(text) {
  const code = unwrap(text);
  if (!code || code.includes('```') || code.includes('\\documentclass') || code.startsWith('{') ||
      /\n\s*#|^(?:here|the equation)\b/i.test(code) ||
      /^(?:[a-z]{2,}\s+){2,}[a-z]{2,}[.!]?\s*$/im.test(code) || !balanced(code)) throw fail('malformed');
  return {
    code, structure: '', confidence: null,
    warnings: ['视觉模型识别结果需对照原图逐字符核对。\\text{[?]} 表示无法确认的字符；模型也可能漏报歧义。']
  };
}

function parseFeynman(text) {
  if (typeof text !== 'string' || text.length > MAX_CODE) throw fail('malformed');
  let value = text.trim();
  const fence = value.match(/^```json\s*\n([\s\S]*)\n?```$/i);
  if (fence) value = fence[1].trim();
  let object;
  try { object = JSON.parse(value); } catch { throw fail('malformed'); }
  if (!isObject(object) || typeof object.code !== 'string' || !object.code.trim() || object.code.length > MAX_CODE ||
      typeof object.structure !== 'string' || !object.structure.trim() || object.structure.length > 10_000 ||
      !Array.isArray(object.uncertainties) || object.uncertainties.length > 100 ||
      object.uncertainties.some((item) => typeof item !== 'string' || item.length > 2000)) throw fail('malformed');
  const code = object.code;
  const active = withoutComments(code);
  if (!/^\s*\\documentclass(?:\[[^\]\r\n]*\])?\s*\{(?:standalone|article)\}/.test(active) ||
      !/\\begin\s*\{document\}/.test(active) || !/\\end\s*\{document\}\s*$/.test(active) ||
      !/\\begin\s*\{tikzpicture\}/.test(active) || !/\\end\s*\{tikzpicture\}/.test(active) ||
      !balanced(code)) throw fail('malformed');
  // This is a format check, not a TeX sandbox. Generated code is never executed.
  // Reject file/shell/Lua access, dynamic command construction, altered catcodes
  // and arbitrary package loads even though the UI only displays editable text.
  if (/\^\^/.test(active) || /\\(?:input|include|includegraphics|write\d*|openout|openin|read\d*|readline|immediate|catcode|csname|endcsname|directlua|latelua|luaexec|special|pdfobj|pdfximage|pdffiledump|scantokens|everyjob|loop|repeat|def|edef|gdef|xdef|let|futurelet|expandafter|newcommand|renewcommand|providecommand|newenvironment|renewenvironment)(?![A-Za-z])/.test(active) ||
      /\\begin\s*\{(?:filecontents\*?|verbatim\*?)\}/.test(active)) throw fail('malformed');
  const allowedPackages = new Set(['tikz', 'tikz-feynman', 'amsmath', 'amssymb', 'amsfonts', 'slashed']);
  let hasTikz = false;
  let packageCount = 0;
  for (const match of active.matchAll(/\\(?:usepackage|RequirePackage)\s*(?:\[[^\]\r\n]*\])?\s*\{([^}]+)\}/g)) {
    packageCount++;
    for (const name of match[1].split(',').map((item) => item.trim())) {
      if (!allowedPackages.has(name)) throw fail('malformed');
      if (name === 'tikz' || name === 'tikz-feynman') hasTikz = true;
    }
  }
  if (!hasTikz || packageCount !== [...active.matchAll(/\\(?:usepackage|RequirePackage)(?![A-Za-z])/g)].length) throw fail('malformed');
  return {
    code, structure: object.structure.trim(), confidence: null,
    warnings: object.uncertainties.map((item) => `待确认：${item}`)
      .concat('实验性结构重建；源码仅做格式检查，未经 LaTeX 编译与物理正确性验证。所需宏包见源码导言区。')
  };
}

module.exports = { unwrap, formatSource, balanced, parseEquation, parseFeynman };
