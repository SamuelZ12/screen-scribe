'use strict';
const {contextBridge,ipcRenderer}=require('electron');
const commands=new Set(['capture','import-image','paste-image','recognize','cancel','update-settings','save-credentials','delete-credentials','test-connection','save-billing','clear-billing','refresh-usage','select-history','save-source','delete-history','clear-history','remove-history-images','copy-source','copy-png','set-pinned','hide','quit','open-data-folder','open-help']);
contextBridge.exposeInMainWorld('screenScribe',Object.freeze({
  getState:()=>ipcRenderer.invoke('screenscribe:state'),
  action:(name,payload={})=>commands.has(name)?ipcRenderer.invoke('screenscribe:action',name,payload):Promise.resolve({ok:false,error:'不支持的操作。'}),
  onState:(callback)=>{
    if(typeof callback!=='function')return ()=>{};
    const listener=(_event,state)=>callback(state);
    ipcRenderer.on('screenscribe:state-changed',listener);
    return ()=>ipcRenderer.removeListener('screenscribe:state-changed',listener);
  },
}));
