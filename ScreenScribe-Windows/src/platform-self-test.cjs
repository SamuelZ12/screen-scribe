'use strict';
// Explicit, offline Windows acceptance test. It uses only a synthetic secret and
// this app's bundled public test image; it never reads a configured account.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {randomUUID}=require('node:crypto');
const {pathToFileURL}=require('node:url');
const {JsonFileStore}=require('./core/storage.cjs');
const {CredentialVault}=require('./core/credentials.cjs');
const {createWindowsCryptoAdapter}=require('./core/os-crypto.cjs');
const {cropRect}=require('./capture/geometry.cjs');
async function run(electron){
  const {app,BrowserWindow,ipcMain,safeStorage,globalShortcut,screen,desktopCapturer,nativeImage,session}=electron;
  const report={kind:'windows-native-self-test',version:app.getVersion(),platform:process.platform,architecture:process.arch,checkedAt:new Date().toISOString(),networkRequests:0,realCredentialsAccessed:false,checks:[],ok:false};
  const folder=fs.mkdtempSync(path.join(os.tmpdir(),'ScreenScribe-Windows-SelfTest-'));
  let win=null,shortcut=null,phase='initialization';
  const check=(name,pass)=>{report.checks.push({name,passed:Boolean(pass)});if(!pass)throw new Error(name);};
  try{
    check('Native Windows process',process.platform==='win32');
    const cryptoAdapter=createWindowsCryptoAdapter(safeStorage);
    check('Windows DPAPI available',await cryptoAdapter.available());
    const vault=new CredentialVault(new JsonFileStore(folder),cryptoAdapter);
    const synthetic={appId:`self-test-${randomUUID()}`,apiKey:`synthetic-${randomUUID()}`};
    await vault.save('mathpix',synthetic);
    const cipher=fs.readFileSync(path.join(folder,'credentials.json'),'utf8');
    check('No plaintext credentials on disk',!cipher.includes(synthetic.apiKey)&&!cipher.includes(synthetic.appId));
    const recovered=await new CredentialVault(new JsonFileStore(folder),cryptoAdapter).load('mathpix');
    check('DPAPI save and fresh-vault reload',recovered.apiKey===synthetic.apiKey&&recovered.appId===synthetic.appId);
    await vault.remove('mathpix');check('Credential deletion',!await vault.status('mathpix'));
    for(const key of ['Control+Alt+Shift+F9','Control+Alt+Shift+F10','Control+Alt+Shift+F11'])if(globalShortcut.register(key,()=>{})){shortcut=key;break;}
    check('Global shortcut registered without elevation',Boolean(shortcut));globalShortcut.unregister(shortcut);shortcut=null;
    const local=session.fromPartition(`self-test-${randomUUID()}`);local.setPermissionRequestHandler((_w,_p,done)=>done(false));local.setPermissionCheckHandler(()=>false);
    local.webRequest.onBeforeRequest((details,done)=>done({cancel:!details.url.startsWith('file:')&&!details.url.startsWith('data:image/')}));
    const root=path.resolve(__dirname,'..'),html=path.join(__dirname,'renderer/index.html'),url=pathToFileURL(html).href;
    const image=nativeImage.createFromPath(path.join(root,'assets/test-equation.png'));
    const size=image.getSize();check('Bundled public fixture decoded',!image.isEmpty()&&size.width>0&&size.height>0);
    const display=screen.getPrimaryDisplay(),work=display.workArea;
    win=new BrowserWindow({x:work.x+24,y:work.y+24,width:716,height:524,show:false,frame:false,thickFrame:false,resizable:false,webPreferences:{preload:path.join(__dirname,'preload.cjs'),sandbox:true,contextIsolation:true,nodeIntegration:false,session:local}});
    let allowedURL=url;
    win.webContents.setWindowOpenHandler(()=>({action:'deny'}));win.webContents.on('will-navigate',(event,target)=>{if(target!==allowedURL)event.preventDefault();});
    const state={version:app.getVersion(),platform:'win32',isDemo:true,settings:{provider:'mathpix',mode:'equation',visionBaseURL:'https://api.openai.com/v1',visionModel:'',captureShortcut:'Control+Shift+L',pasteShortcut:'Control+Shift+V',persistImages:false,monthlyImageLimit:0},credentialStatus:{mathpix:false,vision:false},busy:false,error:null,notice:'离线 Windows 自检 · 内置公开测试图',result:{id:'native-self-test',createdAt:new Date().toISOString(),mode:'equation',provider:'mathpix',code:String.raw`E=mc^2,\qquad x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}`,structure:'',warnings:[],confidence:null,imageDataUrl:image.toDataURL()},history:[],quota:{remaining:null,monthlyUsed:null,detail:'离线自检，未发送 API 请求。',completionRemainder:0,nextRefreshIn:5,stale:false},pinned:true,shortcutError:null};
    let rendererReady=false,patternPaintReady=false;
    ipcMain.handle('screenscribe:state',event=>{if(event.sender!==win.webContents||event.senderFrame!==win.webContents.mainFrame||![url,allowedURL].includes(event.senderFrame.url))throw new Error('source');if(event.senderFrame.url===url)rendererReady=true;else patternPaintReady=true;return state;});
    ipcMain.handle('screenscribe:action',()=>({ok:false,error:'离线自检不调用识别服务。'}));
    await win.loadFile(html);win.show();win.focus();
    const deadline=Date.now()+8000;while(!rendererReady&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,50));
    check('Sandbox renderer and IPC loaded on Windows',rendererReady);
    // The app's own frame rendering is deterministic and contains only the public fixture.
    phase='render application frame';
    const renderedUI=await win.webContents.capturePage();check('Own application frame rendered',!renderedUI.isEmpty()&&renderedUI.getSize().width>500);
    // A full multicolour public pattern avoids false positives from a white
    // desktop or an unrelated white window. The pattern never leaves this PC.
    const colours=['#e82359','#14a5e1','#e6b422','#7a3bd2'];
    let cells='';
    for(let y=0;y<10;y++)for(let x=0;x<10;x++)cells+=`<i style="background:${colours[(x+3*y)%4]}"></i>`;
    const fixture=path.join(folder,'public-test-pattern.html');
    fs.writeFileSync(fixture,`<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-screenscribe-native-test'"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden}body{display:grid;grid-template-columns:repeat(10,1fr);grid-template-rows:repeat(10,1fr)}i{display:block}</style>${cells}<script nonce="screenscribe-native-test">requestAnimationFrame(()=>requestAnimationFrame(()=>window.screenScribe.getState()));</script>`);
    phase='load public multicolour fixture';allowedURL=pathToFileURL(fixture).href;
    await win.loadFile(fixture);win.show();win.focus();
    phase='wait for public fixture compositor frames';
    const paintDeadline=Date.now()+8000;while(!patternPaintReady&&Date.now()<paintDeadline)await new Promise(resolve=>setTimeout(resolve,40));
    check('Public test pattern painted two compositor frames',patternPaintReady);
    phase='render public multicolour fixture';
    const rendered=await win.webContents.capturePage();
    phase='enumerate Windows displays';
    const monitors=screen.getAllDisplays();check('Windows display enumeration',monitors.length>0&&monitors.every(d=>d.bounds.width>0&&d.bounds.height>0));
    await new Promise(resolve=>setTimeout(resolve,250));
    phase='capture public test window desktop';
    const sources=await desktopCapturer.getSources({types:['screen'],thumbnailSize:{width:Math.ceil(display.bounds.width*display.scaleFactor),height:Math.ceil(display.bounds.height*display.scaleFactor)},fetchWindowIcons:false});
    const source=sources.find(s=>s.display_id===String(display.id));check('Desktop source matches physical display',source&&!source.thumbnail.isEmpty());
    const normalized=nativeImage.createFromBuffer(source.thumbnail.toPNG());
    const bounds=win.getBounds(),selection={x:bounds.x-display.bounds.x,y:bounds.y-display.bounds.y,width:bounds.width,height:bounds.height};
    const crop=cropRect(selection,display.bounds,normalized.getSize());
    const selected=normalized.crop(crop);check('Direct selection crop from own test window',!selected.isEmpty()&&selected.getSize().width===crop.width&&selected.getSize().height===crop.height);
    const expected=rendered.getSize(),actual=selected.resize({width:expected.width,height:expected.height});
    const a=actual.getBitmap(),b=rendered.getBitmap();let difference=0,samples=0;
    for(let y=24;y<expected.height-24;y+=12)for(let x=24;x<expected.width-24;x+=12){const offset=(y*expected.width+x)*4;for(let channel=0;channel<3;channel++){difference+=Math.abs(a[offset+channel]-b[offset+channel]);samples++;}}
    check('Selected desktop crop matches unique public multicolour frame',samples>0&&difference/samples<4);
    // Desktop thumbnails stay in memory; no desktop image is written or uploaded.
    report.ok=true;
  }catch(error){
    report.ok=false;report.failedPhase=phase;
    report.errorCategory=/capture page/i.test(String(error.message))?'PAGE_CAPTURE_UNAVAILABLE':null;
    report.errorCode=typeof error.code==='string'&&/^[A-Z0-9_]{1,80}$/.test(error.code)?error.code:null;
    report.errorName=typeof error.name==='string'&&/^[A-Za-z]{1,40}$/.test(error.name)?error.name:'Error';
    if(!report.checks.some(c=>!c.passed))report.checks.push({name:'Native test completed without runtime exception',passed:false});
  }finally{
    if(shortcut)globalShortcut.unregister(shortcut);
    if(win&&!win.isDestroyed())win.destroy();
    ipcMain.removeHandler('screenscribe:state');ipcMain.removeHandler('screenscribe:action');
    fs.rmSync(folder,{recursive:true,force:true});
  }
  const output=JSON.stringify(report,null,2)+'\n';
  const outputPath=path.join(app.getPath('temp'),'ScreenScribe-Windows-self-test.json');fs.writeFileSync(outputPath,output,{mode:0o600});
  console.log(JSON.stringify(report));app.exit(report.ok?0:1);
}
module.exports={run};
