'use strict';
const DEFAULTS = Object.freeze({
  provider: 'mathpix', mode: 'equation', visionBaseURL: 'https://api.openai.com/v1', visionModel: '',
  captureShortcut: 'CommandOrControl+Shift+L', pasteShortcut: 'CommandOrControl+Shift+V',
  persistImages: false, monthlyImageLimit: 0,
});
function userError(message){const error=new Error(message);error.safeMessage=message;return error;}
function canonicalShortcut(value) {
  if (typeof value !== 'string' || value.length > 90 || !/^(?:(?:CommandOrControl|Control|Alt|Shift|Super)\+){1,4}(?:[A-Z0-9]|F(?:[1-9]|1[0-9]|2[0-4])|Space|PrintScreen)$/i.test(value)) return null;
  const parts=value.toLowerCase().split('+'),key=parts.pop();
  const modifiers=parts.map(x=>x==='commandorcontrol'?'control':x);
  if(new Set(modifiers).size!==modifiers.length||!modifiers.some(x=>['control','alt','super'].includes(x)))return null;
  const names={control:'Control',alt:'Alt',shift:'Shift',super:'Super'};
  return ['control','alt','shift','super'].filter(x=>modifiers.includes(x)).map(x=>names[x]).concat(key==='space'?'Space':key==='printscreen'?'PrintScreen':key.toUpperCase()).join('+');
}
function validShortcut(value) {return canonicalShortcut(value)!==null;}
function sanitizeSettings(input, base=DEFAULTS) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw userError('设置格式无效。');
  const out={...base};
  for (const [key,value] of Object.entries(input)) {
    if (!Object.hasOwn(DEFAULTS,key)) throw userError('包含不支持的设置。');
    if (key==='provider') {if (!['mathpix','vision'].includes(value)) throw userError('请选择有效的识别服务。');}
    else if (key==='mode') {if (!['equation','feynman'].includes(value)) throw userError('请选择有效的识别模式。');}
    else if (key==='persistImages') {if(typeof value!=='boolean') throw userError('原图设置无效。');}
    else if (key==='monthlyImageLimit') {if(!Number.isSafeInteger(value)||value<0||value>1_000_000_000) throw userError('月上限必须是非负整数。');}
    else if (key.endsWith('Shortcut')) {if(!validShortcut(value)) throw userError('快捷键格式应类似 Control+Shift+L，且需含 Control 或 Alt。');out[key]=canonicalShortcut(value);continue;}
    else if (key==='visionModel') {if(typeof value!=='string'||value.length>200||/[\r\n\0]/.test(value)) throw userError('模型名称无效。');}
    else if (key==='visionBaseURL') {if(typeof value!=='string'||value.length>2048) throw userError('API 根地址无效。');}
    out[key]=typeof value==='string'?value.trim():value;
  }
  if(canonicalShortcut(out.captureShortcut)===canonicalShortcut(out.pasteShortcut)) throw userError('框选与粘贴快捷键不能相同。');
  return out;
}
class SettingsStore {
  constructor(store) {this.store=store;this.error=null;try{this.value=sanitizeSettings(store.read('settings.json',DEFAULTS));}catch{this.value={...DEFAULTS};this.error='设置文件无法读取，已使用默认值。请在设置中确认后保存。';}}
  save(patch) {const next=sanitizeSettings(patch,this.value);this.store.write('settings.json',next);this.value=next;return next;}
}
module.exports={DEFAULTS,SettingsStore,sanitizeSettings,validShortcut,canonicalShortcut};
