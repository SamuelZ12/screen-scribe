'use strict';
const {randomUUID}=require('node:crypto');
const {SettingsStore,sanitizeSettings}=require('./settings.cjs');
const services=require('../services/providers.cjs');
class UserError extends Error {constructor(message){super(message);this.safeMessage=message;}}
const problem=message=>{throw new UserError(message);};
const validText=(value,max=100000)=>typeof value==='string'&&value.length<=max&&!value.includes('\0');
class Controller {
  constructor({storage,vault,history,credit,io,demo=false,version='0.1.0',onChange=()=>{},providers=services}) {
    Object.assign(this,{storage,vault,history,credit,io,demo,version,onChange,providers});
    this.settingsStore=new SettingsStore(storage);this.settings=this.settingsStore.value;
    this.credentialStatus={mathpix:false,vision:false};this.credentials=new Map();
    this.result=null;this.currentPNG=null;this.busy=false;this.error=null;this.notice=null;this.pinned=false;this.shortcutError=null;
    this.epoch=0;this.request=null;this.usageRequest=null;this.usageError=null;this.capturePending=false;
  }
  async initialize() {
    try {
      await this.refreshCredentialStatus();
      if(this.credentialStatus.mathpix){const value=await this.getCredentials('mathpix');this.credit.selectAccount(value?.appId||'');}
    } catch(error) {this.error=error.safeMessage||'无法读取已保存的配置，请在设置中重新保存凭据。';}
    if(this.demo) {
      const code=String.raw`E=mc^2,\qquad x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}`;
      const imageDataUrl=this.io.testPNG?`data:image/png;base64,${this.io.testPNG.toString('base64')}`:undefined;
      this.result={id:randomUUID(),createdAt:new Date().toISOString(),mode:'equation',provider:'mathpix',model:'',code,structure:'',warnings:['本地演示，未调用识别 API。'],confidence:null,imageDataUrl};
      this.currentPNG=this.io.testPNG||null;
      this.notice='演示模式 · 不截图、不读取凭据、不调用 API、不保存本机数据';
    }
    this.emit();
    if(!this.demo&&this.credentialStatus.mathpix)void this.refreshUsage().catch(()=>{this.usageError='用量暂时不可用，请手动刷新。';this.emit();});
  }
  scope(provider,baseURL=this.settings.visionBaseURL){return provider==='mathpix'?'mathpix':`vision:${this.providers.normalizeVisionBase(baseURL)}`;}
  async getCredentials(provider,baseURL=this.settings.visionBaseURL) {
    const key=this.scope(provider,baseURL);
    if(this.credentials.has(key))return this.credentials.get(key);
    const epoch=this.epoch,value=await this.vault.load(provider,provider==='vision'?this.providers.normalizeVisionBase(baseURL):undefined);
    if(epoch!==this.epoch)return null;
    this.credentials.set(key,value);return value;
  }
  async refreshCredentialStatus(){
    this.credentialStatus={mathpix:await this.vault.status('mathpix'),vision:await this.vault.status('vision',this.providers.normalizeVisionBase(this.settings.visionBaseURL))};
  }
  state() {
    const quota=this.credit.snapshot(this.settings.monthlyImageLimit);
    if(this.usageError)quota.detail=[quota.detail,this.usageError].filter(Boolean).join('\n');
    return {version:this.version,platform:this.io.platform||process.platform,isDemo:this.demo,settings:{...this.settings},credentialStatus:{...this.credentialStatus},busy:this.busy,error:this.error,notice:this.notice,result:this.result,history:this.history.list(),quota,pinned:this.pinned,shortcutError:this.shortcutError};
  }
  emit(){this.onChange(this.state());}
  async action(name,payload={}) {
    try {
      if(!payload||typeof payload!=='object'||Array.isArray(payload))problem('操作参数无效。');
      const handler=Object.hasOwn(this.actions,name)?this.actions[name]:null;if(!handler)problem('不支持的操作。');
      await handler.call(this,payload);return {ok:true};
    } catch(error) {
      this.error=typeof error?.safeMessage==='string'?error.safeMessage:'操作未完成，请检查配置、文件与网络后重试。';
      this.emit();return {ok:false,error:this.error};
    }
  }
  cancel(){this.epoch++;this.request?.abort();this.request=null;this.io.cancelCapture?.();this.capturePending=false;this.busy=false;}
  async chooseImage(kind) {
    if(this.busy)problem('当前任务正在进行，请先取消。');
    this.error=null;this.notice=null;this.busy=true;this.capturePending=true;const epoch=this.epoch;this.emit();
    try {
      const png=await this.io[kind]();
      if(epoch!==this.epoch)return;
      if(!png){this.notice='已取消选取。';return;}
      this.busy=false;this.capturePending=false;
      await this.recognize(png);
    }finally{if(epoch===this.epoch){this.busy=false;this.capturePending=false;this.emit();}}
  }
  async recognize(png,{test=false}={}) {
    if(this.busy)problem('当前任务正在进行，请先取消。');
    if(!Buffer.isBuffer(png)||!png.length)problem('请先框选、导入或粘贴一张图片。');
    const cfg={...this.settings},mode=test?'equation':cfg.mode;
    if(mode==='feynman'&&cfg.provider==='mathpix')problem('费曼图重建请切换到兼容视觉模型，Mathpix 仅用于公式。');
    if(this.demo){this.notice='这是本地演示，不发送图片。Windows 正式版可使用你自己的 API。';this.emit();return;}
    this.error=null;this.notice=test?'正在发送内置公开测试图，可能计费…':'正在识别选中的图片…';
    this.busy=true;const epoch=this.epoch,request=new AbortController();this.request=request;
    if(!test){
      this.currentPNG=Buffer.from(png);
      this.result={id:randomUUID(),createdAt:new Date().toISOString(),mode,provider:cfg.provider,model:cfg.provider==='vision'?cfg.visionModel:'',code:'',structure:'',warnings:[],confidence:null,imageDataUrl:`data:image/png;base64,${png.toString('base64')}`};
    }
    this.emit();
    try {
      const credentials=await this.getCredentials(cfg.provider);
      if(epoch!==this.epoch||request.signal.aborted)return;
      if(!credentials)problem('请先在设置中保存此服务的 API 凭据。');
      const output=cfg.provider==='mathpix'?await this.providers.recognizeMathpix({png,...credentials,signal:request.signal,
        beforeSend:()=>{if(this.credit.recordAttempt(credentials.appId)===false)problem('本地用量计数无法保存，已停止发送。');this.emit();},
        afterSend:async()=>{const due=this.credit.recordCompletion(credentials.appId);this.emit();if(due&&epoch===this.epoch)await this.refreshUsage();},
      }):await this.providers.recognizeVision({png,...credentials,baseURL:cfg.visionBaseURL,model:cfg.visionModel,mode,signal:request.signal});
      if(epoch!==this.epoch)return;
      if(test){this.notice=`连接成功 · ${output.code.slice(0,120)}`;return;}
      const entry={id:randomUUID(),createdAt:new Date().toISOString(),mode,provider:cfg.provider,model:cfg.provider==='vision'?cfg.visionModel:'',...output,imageDataUrl:`data:image/png;base64,${png.toString('base64')}`};
      this.result=entry;
      try{this.history.add(entry,{persistImages:cfg.persistImages});this.notice='识别完成';}
      catch(error){this.error=error.safeMessage||'历史未能写入，当前结果仍可复制。';this.notice='识别完成，结果仅保留在当前面板。';}
    } catch(error) {
      if(epoch!==this.epoch)return;
      if(request.signal.aborted){this.notice='已取消。';return;}
      throw error;
    } finally {
      if(epoch===this.epoch){this.busy=false;this.request=null;this.emit();}
    }
  }
  async refreshUsage() {
    if(this.demo){this.notice='演示模式不查询账户。';this.emit();return;}
    if(this.usageRequest)return this.usageRequest.promise;
    if(!this.credentialStatus.mathpix)problem('请先保存 Mathpix 凭据，再查询用量。');
    const epoch=this.epoch,abort=new AbortController(),task={abort,promise:null};
    this.usageRequest=task;
    task.promise=(async()=>{
      try {
        const credentials=await this.getCredentials('mathpix');
        if(epoch!==this.epoch||abort.signal.aborted)return;
        if(!credentials)problem('请先保存 Mathpix 凭据。');
        const snapshot=await this.providers.fetchMathpixUsage({...credentials,signal:abort.signal});
        if(epoch!==this.epoch||abort.signal.aborted)return;
        this.credit.reconcile(snapshot);this.usageError=null;
      } catch(error) {
        if(epoch!==this.epoch||abort.signal.aborted)return;
        this.usageError=error.safeMessage||'官方用量暂时不可用，保留已扣减的本地估算。';
      } finally {if(this.usageRequest===task)this.usageRequest=null;this.emit();}
    })();
    return task.promise;
  }
  invalidate(){this.cancel();this.usageRequest?.abort.abort();this.usageRequest=null;}
  get actions(){return ACTIONS;}
}
const ACTIONS=Object.freeze({
  async capture(){await this.chooseImage('capture');},
  async 'import-image'(){await this.chooseImage('importImage');},
  async 'paste-image'(){await this.chooseImage('pasteImage');},
  async recognize(){await this.recognize(this.currentPNG);},
  cancel(){this.cancel();this.notice='已取消。';this.emit();},
  async 'test-connection'(){await this.recognize(this.io.testPNG,{test:true});},
  async 'update-settings'(patch){
    if('visionBaseURL' in patch)patch={...patch,visionBaseURL:this.providers.normalizeVisionBase(patch.visionBaseURL)};
    const next=sanitizeSettings(patch,this.settings),previous=this.settings;
    const shortcutError=this.io.registerShortcuts(next);if(shortcutError)problem(shortcutError);
    this.invalidate();
    try{this.settings=this.settingsStore.save(patch);}catch(error){this.io.registerShortcuts(previous);throw error;}
    await this.refreshCredentialStatus();this.shortcutError=null;
    this.notice='设置已保存。';this.error=null;this.emit();
  },
  async 'save-credentials'(payload){
    if(this.demo)problem('演示模式不保存凭据，请在 Windows 正式版配置。');
    if(!['mathpix','vision'].includes(payload.provider))problem('服务类型无效。');
    this.invalidate();const base=payload.provider==='vision'?this.providers.normalizeVisionBase(payload.baseURL||this.settings.visionBaseURL):undefined;
    if(payload.provider==='vision'&&base!==this.providers.normalizeVisionBase(this.settings.visionBaseURL))problem('请先保存 API 根地址，再为此地址保存专用密钥。');
    const value=payload.provider==='mathpix'?{appId:payload.appId,apiKey:payload.apiKey}:{apiKey:payload.apiKey};
    await this.vault.save(payload.provider,value,base);this.credentials.delete(this.scope(payload.provider,base));await this.refreshCredentialStatus();
    if(payload.provider==='mathpix'){const saved=await this.getCredentials('mathpix');this.credit.selectAccount(saved.appId);}
    this.notice='凭据已加密保存。';this.error=null;this.emit();if(payload.provider==='mathpix')await this.refreshUsage();
  },
  async 'delete-credentials'(payload){
    if(this.demo)problem('演示模式没有保存的凭据。');
    if(!['mathpix','vision'].includes(payload.provider))problem('服务类型无效。');
    this.invalidate();const base=payload.provider==='vision'?this.providers.normalizeVisionBase(payload.baseURL||this.settings.visionBaseURL):undefined;
    await this.vault.remove(payload.provider,base);this.credentials.delete(this.scope(payload.provider,base));
    if(payload.provider==='mathpix')this.credit.selectAccount('');await this.refreshCredentialStatus();
    this.notice='对应凭据已删除。';this.error=null;this.emit();
  },
  async 'save-billing'(payload){
    if(this.demo)problem('演示模式不保存真实账单。');
    const credentials=await this.getCredentials('mathpix');if(!credentials)problem('请先保存 Mathpix 凭据，以隔离账号额度。');
    if(this.busy)problem('请先结束当前识别，再保存账单快照。');
    this.usageRequest?.abort.abort();this.usageRequest=null;
    this.credit.selectAccount(credentials.appId);this.credit.saveBilling(payload);this.notice='账单快照已保存；总剩余为保守估算。';this.error=null;this.emit();await this.refreshUsage();
  },
  'clear-billing'(){this.credit.clearBilling();this.notice='账单快照已清除。';this.emit();},
  async 'refresh-usage'(){await this.refreshUsage();},
  'select-history'({id}){
    if(!validText(id,100))problem('历史记录无效。');
    const entry=this.history.list().find(x=>x.id===id);if(!entry)problem('这条记录已不存在。');
    this.cancel();this.result={...entry};this.currentPNG=entry.imageDataUrl?Buffer.from(entry.imageDataUrl.split(',')[1],'base64'):null;this.error=null;this.notice=null;this.emit();
  },
  'save-source'({code}){
    if(!this.result)problem('当前没有可编辑的结果。');if(!validText(code)||!code.trim())problem('请输入有效源码（最多十万字符）。');
    const updated=this.history.update(this.result.id,code);
    if(!updated)this.history.add({...this.result,code},{persistImages:this.settings.persistImages});
    this.result={...this.result,code};this.notice='修改已保存。';this.emit();
  },
  'delete-history'({id}){const selected=id||this.result?.id;if(selected)this.history.remove(selected);if(this.result?.id===selected){this.result=null;this.currentPNG=null;}this.notice='已删除记录。';this.emit();},
  'clear-history'(){this.history.clear();this.result=null;this.currentPNG=null;this.notice='历史记录已清空。';this.emit();},
  'remove-history-images'(){this.history.removeImages();this.notice='历史中的原图已移除，当前图片仅保留在内存。';this.emit();},
  'copy-source'({format='plain'}){if(!this.result)problem('当前没有识别结果。');if(!['plain','inline','display','equation','bracket'].includes(format))problem('复制格式无效。');this.io.copyText(this.providers.formatSource(this.result.code,format));this.notice='已复制源码。';this.emit();},
  'copy-png'(){if(!this.currentPNG)problem('此记录没有保存原图。');this.io.copyPNG(this.currentPNG);this.notice='已复制原图。';this.emit();},
  'set-pinned'({value}){if(typeof value!=='boolean')problem('固定设置无效。');this.pinned=value;this.io.setPinned(value);this.emit();},
  hide(){this.io.hide();},quit(){this.io.quit();},
  'open-data-folder'(){this.io.openDataFolder();},'open-help'(){this.io.openHelp();},
});
module.exports={Controller,UserError};
