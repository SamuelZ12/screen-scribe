'use strict';
// Electron 45's async decrypt API returns {result, shouldReEncrypt}, not string.
// Keep platform checks here so demo/Mac runs cannot touch any OS keychain.
function fail(){const error=new Error('Windows 加密服务暂不可用，请重新启动后再保存凭据。');error.safeMessage=error.message;return error;}
function createWindowsCryptoAdapter(safeStorage,{platform=process.platform,enabled=true}={}){
 const permitted=enabled&&platform==='win32';
 return {
  async available(){
   if(!permitted||typeof safeStorage.isAsyncEncryptionAvailable!=='function')return false;
   try{return await safeStorage.isAsyncEncryptionAvailable()===true;}catch{return false;}
  },
  async encrypt(text){
   if(!permitted||typeof text!=='string'||typeof safeStorage.encryptStringAsync!=='function')throw fail();
   try{const bytes=await safeStorage.encryptStringAsync(text);if(!Buffer.isBuffer(bytes)||!bytes.length)throw fail();return bytes;}catch{throw fail();}
  },
  async decrypt(bytes){
   if(!permitted||!Buffer.isBuffer(bytes)||typeof safeStorage.decryptStringAsync!=='function')throw fail();
   try{const value=await safeStorage.decryptStringAsync(bytes);if(!value||typeof value.result!=='string'||typeof value.shouldReEncrypt!=='boolean')throw fail();return value.result;}catch{throw fail();}
  },
 };
}
module.exports={createWindowsCryptoAdapter};
