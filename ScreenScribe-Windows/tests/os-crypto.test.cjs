'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {createWindowsCryptoAdapter}=require('../src/core/os-crypto.cjs');
test('Windows adapter decodes Electron 45 async return object and preserves encrypted bytes',async()=>{
 let calls=0;
 const adapter=createWindowsCryptoAdapter({isAsyncEncryptionAvailable:async()=>true,encryptStringAsync:async text=>Buffer.from('encrypted:'+text),decryptStringAsync:async bytes=>{calls++;return {result:bytes.toString().slice(10),shouldReEncrypt:false};}},{platform:'win32'});
 assert.equal(await adapter.available(),true);const bytes=await adapter.encrypt('synthetic-only');assert.equal(await adapter.decrypt(bytes),'synthetic-only');assert.equal(calls,1);
});
test('DPAPI rotated-key metadata still returns the recovered string without losing it',async()=>{
 const adapter=createWindowsCryptoAdapter({decryptStringAsync:async()=>({result:'synthetic-recovered',shouldReEncrypt:true})},{platform:'win32'});
 assert.equal(await adapter.decrypt(Buffer.from('ciphertext')),'synthetic-recovered');
});
test('Mac and demo adapters never invoke any operating-system cryptography',async()=>{
 let calls=0;const os=new Proxy({},{get(){calls++;throw Error('must not touch OS');}});
 for(const config of [{platform:'darwin'},{platform:'win32',enabled:false}]){const adapter=createWindowsCryptoAdapter(os,config);assert.equal(await adapter.available(),false);await assert.rejects(adapter.encrypt('fake'));await assert.rejects(adapter.decrypt(Buffer.from('fake')));}
 assert.equal(calls,0);
});
test('Unexpected decrypt shapes cannot be parsed as credentials',async()=>{
 for(const value of ['plaintext',{result:4,shouldReEncrypt:false},{result:'x'},null]){
  const adapter=createWindowsCryptoAdapter({decryptStringAsync:async()=>value},{platform:'win32'});
  await assert.rejects(adapter.decrypt(Buffer.from('fake')),error=>error.safeMessage&&!error.message.includes('plaintext'));
 }
});
test('Unavailable or failing OS crypto has a fixed message and no plaintext fallback',async()=>{
 const adapter=createWindowsCryptoAdapter({isAsyncEncryptionAvailable:async()=>{throw Error('private OS details');},encryptStringAsync:async()=>{throw Error('private OS details');},decryptStringAsync:async()=>{throw Error('private OS details');}},{platform:'win32'});
 assert.equal(await adapter.available(),false);await assert.rejects(adapter.encrypt('fake'),error=>!error.message.includes('private'));await assert.rejects(adapter.decrypt(Buffer.from('fake')),error=>!error.message.includes('private'));
});
