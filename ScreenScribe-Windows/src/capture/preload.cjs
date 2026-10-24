'use strict';
const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('captureBridge',Object.freeze({
  getState:()=>ipcRenderer.invoke('screenscribe:capture-state'),
  finish:(rectangle)=>ipcRenderer.invoke('screenscribe:capture-finish',rectangle),
  cancel:()=>ipcRenderer.invoke('screenscribe:capture-cancel'),
}));
