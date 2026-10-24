'use strict';
const {app,BrowserWindow,Tray,Menu,screen,globalShortcut,desktopCapturer,nativeImage,clipboard,dialog,ipcMain,safeStorage,shell,session}=require('electron');
const path=require('node:path');
const fs=require('node:fs');
const {fileURLToPath,pathToFileURL}=require('node:url');
const {JsonFileStore}=require('./core/storage.cjs');
const {CredentialVault}=require('./core/credentials.cjs');
const {HistoryStore}=require('./core/history.cjs');
const {CreditStore}=require('./core/credit.cjs');
const {Controller,UserError}=require('./core/controller.cjs');
const {cropRect,panelPosition}=require('./capture/geometry.cjs');
const root=path.resolve(__dirname,'..');
const rendererPath=path.join(__dirname,'renderer/index.html'),overlayPath=path.join(__dirname,'capture/overlay.html');
const smoke=process.argv.includes('--smoke-test'),nativeTest=process.argv.includes('--platform-self-test'),demo=smoke||process.argv.includes('--demo');
let window=null,tray=null,controller=null,quitting=false,localSession=null,captureSession=null,captureGeneration=0;
let registered=new Map(),smokeTimer=null,smokeFinished=false;
app.setName('ScreenScribe Windows');
app.setAppUserModelId('org.screenscribe.windows');
// This independently named profile can never collide with the mature macOS app.
if(smoke)app.setPath('userData',path.join(app.getPath('temp'),`ScreenScribe-Windows-Smoke-${process.pid}`));
else if(nativeTest)app.setPath('userData',path.join(app.getPath('temp'),'ScreenScribe-Windows-NativeTest'));
else if(demo)app.setPath('userData',path.join(app.getPath('temp'),'ScreenScribe-Windows-Demo'));
else app.setPath('userData',path.join(app.getPath('appData'),'ScreenScribe-Windows'));
if(!demo&&process.platform!=='win32'){
  console.error('ScreenScribe Windows 正式运行需要 Windows 10/11；本机仅可使用 npm run demo。');app.quit();
}else if(!app.requestSingleInstanceLock()){if(smoke||nativeTest)app.exit(1);else app.quit();}
else {
  app.on('second-instance',()=>showPanel());
  app.whenReady().then(()=>nativeTest?require('./platform-self-test.cjs').run(require('electron')):start()).catch(()=>{console.error('ScreenScribe 初始化未完成，请检查本机数据目录。');app.exit(1);});
}
function allowedFile(url){
  try{if(!url.startsWith('file:'))return url.startsWith('data:image/');const file=fileURLToPath(url);const relative=path.relative(root,file);return relative!==''&&!relative.startsWith('..')&&!path.isAbsolute(relative);}
  catch{return false;}
}
function secureSession(){
  const value=session.fromPartition('screenscribe-local');
  value.setPermissionRequestHandler((_wc,_permission,done)=>done(false));
  value.setPermissionCheckHandler(()=>false);
  value.webRequest.onBeforeRequest((details,done)=>done({cancel:!allowedFile(details.url)}));
  return value;
}
function prefs(preload){return {preload,contextIsolation:true,sandbox:true,nodeIntegration:false,nodeIntegrationInWorker:false,nodeIntegrationInSubFrames:false,webSecurity:true,allowRunningInsecureContent:false,spellcheck:false,session:localSession};}
function secureWindow(target,expectedPath){
  const expected=pathToFileURL(expectedPath).href;
  target.webContents.setWindowOpenHandler(()=>({action:'deny'}));
  target.webContents.on('will-navigate',(event,url)=>{if(url!==expected)event.preventDefault();});
  target.webContents.on('will-attach-webview',event=>event.preventDefault());
  target.webContents.on('render-process-gone',()=>{if(!target.isDestroyed()&&target===window){controller.error='界面进程已停止，请退出后重新启动。';}});
}
function mainSender(event){
  return window&&!window.isDestroyed()&&event.sender===window.webContents&&event.senderFrame===window.webContents.mainFrame&&event.senderFrame.url===pathToFileURL(rendererPath).href;
}
function captureSender(event){
  const item=captureSession?.windows.get(event.sender.id);
  return item&&event.senderFrame===item.window.webContents.mainFrame&&event.senderFrame.url===pathToFileURL(overlayPath).href?item:null;
}
function memoryStore(){const data=new Map();return{read:(name,fallback)=>structuredClone(data.has(name)?data.get(name):fallback),write:(name,value)=>data.set(name,structuredClone(value))};}
async function cryptoAvailable(){
  if(process.platform!=='win32'||demo)return false;
  return typeof safeStorage.isAsyncEncryptionAvailable==='function'?await safeStorage.isAsyncEncryptionAvailable():safeStorage.isEncryptionAvailable();
}
async function start(){
  app.setAccessibilitySupportEnabled(true);
  localSession=secureSession();
  screen.on('display-removed',()=>cancelCapture());
  screen.on('display-metrics-changed',()=>cancelCapture());
  const storage=demo?memoryStore():new JsonFileStore(app.getPath('userData'));
  const cryptoAdapter={available:cryptoAvailable,
    encrypt:async value=>typeof safeStorage.encryptStringAsync==='function'?await safeStorage.encryptStringAsync(value):safeStorage.encryptString(value),
    decrypt:async value=>typeof safeStorage.decryptStringAsync==='function'?await safeStorage.decryptStringAsync(value):safeStorage.decryptString(value),
  };
  const vault=new CredentialVault(storage,cryptoAdapter),history=new HistoryStore(storage),credit=new CreditStore(storage);
  const io={platform:process.platform,testPNG:fs.readFileSync(path.join(root,'assets/test-equation.png')),
    capture:beginCapture,cancelCapture:()=>cancelCapture(),importImage,pasteImage,
    copyText:value=>clipboard.writeText(value),copyPNG:value=>clipboard.writeImage(nativeImage.createFromBuffer(value)),
    hide:()=>window?.hide(),quit:()=>app.quit(),setPinned:value=>window?.setAlwaysOnTop(value,'floating'),
    registerShortcuts,openDataFolder:()=>{if(!demo)void shell.openPath(app.getPath('userData'));},
    openHelp:()=>void shell.openPath(app.isPackaged?path.join(process.resourcesPath,'使用说明.txt'):path.join(root,'docs/使用说明.txt')),
  };
  controller=new Controller({storage,vault,history,credit,io,demo,version:app.getVersion(),onChange:state=>{
    if(window&&!window.isDestroyed())window.webContents.send('screenscribe:state-changed',state);
  }});
  await controller.initialize();
  createWindow();createTray();controller.shortcutError=registerShortcuts(controller.settings);
  ipcMain.handle('screenscribe:state',event=>{
    if(!mainSender(event))throw new Error('无效页面来源。');
    if(smoke&&!smokeFinished){smokeFinished=true;clearTimeout(smokeTimer);console.log(JSON.stringify({ok:true,platform:process.platform,version:app.getVersion(),rendererBridge:true,demo:true}));setTimeout(()=>app.quit(),800);}
    return controller.state();
  });
  ipcMain.handle('screenscribe:action',(event,name,payload)=>{
    if(!mainSender(event)||typeof name!=='string'||name.length>50)return{ok:false,error:'无效页面来源。'};
    return controller.action(name,payload);
  });
  ipcMain.handle('screenscribe:capture-state',event=>{
    const item=captureSender(event);if(!item)throw new Error('无效选区来源。');
    return {imageDataUrl:item.image.toDataURL(),width:item.display.bounds.width,height:item.display.bounds.height};
  });
  ipcMain.handle('screenscribe:capture-finish',(event,rect)=>{
    const item=captureSender(event);if(!item)return{ok:false};
    try{const physical=cropRect(rect,item.display.bounds,item.image.getSize());const png=item.image.crop(physical).toPNG();finishCapture(png);return{ok:true};}
    catch{finishCapture(null);controller.error='选区无效，请重新框选。';controller.emit();return{ok:false};}
  });
  ipcMain.handle('screenscribe:capture-cancel',event=>{if(captureSender(event))finishCapture(null);return{ok:true};});
  const firstLaunch=!demo&&!controller.credentialStatus.mathpix&&!controller.credentialStatus.vision;
  if(firstLaunch)controller.notice='首次使用：请先点齿轮，保存自己的识别 API 凭据。';
  if(demo||firstLaunch||process.argv.includes('--show'))showPanel();
  if(smoke)smokeTimer=setTimeout(()=>{if(!smokeFinished){console.error('Renderer bridge smoke timeout');app.exit(1);}},15000);
  if(history.error||controller.settingsStore.error){controller.error=history.error||controller.settingsStore.error;controller.emit();showPanel();}
}
function createWindow(){
  const display=screen.getPrimaryDisplay(),bounds=display.workArea;
  window=new BrowserWindow({width:Math.min(716,bounds.width),height:Math.min(524,bounds.height),minWidth:560,minHeight:460,show:false,frame:false,backgroundColor:'#ffffff',skipTaskbar:true,resizable:true,maximizable:false,minimizable:false,autoHideMenuBar:true,icon:path.join(root,'assets/icon.png'),title:'ScreenScribe',webPreferences:prefs(path.join(__dirname,'preload.cjs'))});
  secureWindow(window,rendererPath);window.setMenu(null);
  window.on('close',event=>{if(!quitting){event.preventDefault();window.hide();}});
  window.on('blur',()=>{if(!demo&&!controller?.pinned&&!captureSession)window.hide();});
  window.webContents.on('did-fail-load',(_event,code)=>{if(code!==-3){console.error('本地界面载入失败。');if(smoke)app.exit(1);}});
  void window.loadFile(rendererPath);
}
function showPanel(){
  if(!window||window.isDestroyed())return;
  if(!window.isVisible()&&tray){const bounds=tray.getBounds();const display=screen.getDisplayNearestPoint({x:bounds.x,y:bounds.y});window.setBounds(panelPosition(bounds,display,{width:window.getBounds().width,height:window.getBounds().height}));}
  window.show();window.focus();controller?.emit();
}
function createTray(){
  tray=new Tray(path.join(root,'assets/tray.png'));tray.setToolTip('ScreenScribe · Ctrl+Shift+L 框选公式');
  tray.on('click',()=>window?.isVisible()?window.hide():showPanel());
  tray.setContextMenu(Menu.buildFromTemplate([
    {label:'打开 ScreenScribe',click:()=>showPanel()},
    {label:'直接框选公式',click:()=>void controller.action('capture')},
    {label:'粘贴截图识别',click:()=>void controller.action('paste-image')},
    {type:'separator'},
    {label:'退出',click:()=>app.quit()},
  ]));
}
function registerShortcuts(settings){
  if(demo)return null;
  const desired=new Map([[settings.captureShortcut.replace(/CommandOrControl/gi,'Control'),'capture'],[settings.pasteShortcut.replace(/CommandOrControl/gi,'Control'),'paste-image']]),added=[];
  try{
    for(const [key,command]of desired){
      if(registered.has(key))continue;
      if(!globalShortcut.register(key,()=>void controller.action(registered.get(key)||command)))throw new Error('conflict');
      added.push(key);
    }
    for(const key of registered.keys())if(!desired.has(key))globalShortcut.unregister(key);
    registered=desired;return null;
  }catch{
    for(const key of added)globalShortcut.unregister(key);
    return '快捷键被系统或其他应用占用，请在设置中更换组合。';
  }
}
function normalizeImage(image){
  if(image.isEmpty())throw new UserError('没有可用图片，请导入图片或先执行 Win+Shift+S。');
  const size=image.getSize();if(size.width<1||size.height<1||size.width>32768||size.height>32768||size.width*size.height>80_000_000)throw new UserError('图片尺寸过大，请缩小选区。');
  const png=image.toPNG();if(png.length>10_000_000)throw new UserError('图片超过 10 MB，请缩小选区。');return png;
}
async function importImage(){
  if(demo)return fs.readFileSync(path.join(root,'assets/test-equation.png'));
  const chosen=await dialog.showOpenDialog(window,{title:'选择公式或费曼图图片',properties:['openFile'],filters:[{name:'图片',extensions:['png','jpg','jpeg','webp','bmp']} ]});
  if(chosen.canceled||chosen.filePaths.length!==1)return null;
  try{
    const info=fs.statSync(chosen.filePaths[0]);if(!info.isFile()||info.size>20_000_000)throw new Error('size');
    return normalizeImage(nativeImage.createFromBuffer(fs.readFileSync(chosen.filePaths[0])));
  }catch(error){if(error instanceof UserError)throw error;throw new UserError('无法读取这张图片，请选择有效的 PNG、JPEG 或 WebP 文件。');}
}
async function pasteImage(){if(demo)return fs.readFileSync(path.join(root,'assets/test-equation.png'));return normalizeImage(clipboard.readImage());}
async function beginCapture(){
  if(demo){showPanel();return fs.readFileSync(path.join(root,'assets/test-equation.png'));}
  if(captureSession)throw new UserError('框选已在进行。');
  const generation=++captureGeneration;
  window.hide();await new Promise(resolve=>setTimeout(resolve,220));
  if(generation!==captureGeneration)return null;
  const displays=screen.getAllDisplays();
  const maxWidth=Math.max(...displays.map(d=>Math.ceil(d.bounds.width*d.scaleFactor)));
  const maxHeight=Math.max(...displays.map(d=>Math.ceil(d.bounds.height*d.scaleFactor)));
  let sources;
  try{sources=await desktopCapturer.getSources({types:['screen'],thumbnailSize:{width:maxWidth,height:maxHeight},fetchWindowIcons:false});}
  catch{if(generation!==captureGeneration)return null;showPanel();throw new UserError('Windows 未提供可用屏幕画面。请检查远程会话状态，或用 Win+Shift+S 后粘贴。');}
  if(generation!==captureGeneration)return null;
  const selected=displays.map(display=>{
    const source=sources.find(s=>s.display_id===String(display.id));
    if(!source||source.thumbnail.isEmpty())return null;
    return {display,image:nativeImage.createFromBuffer(source.thumbnail.toPNG())};
  }).filter(Boolean);
  sources=null;
  if(!selected.length){showPanel();throw new UserError('无法匹配屏幕画面与显示器，已停止框选以避免截错位置。请用 Win+Shift+S 后粘贴。');}
  return new Promise((resolve,reject)=>{
    captureSession={windows:new Map(),resolve,reject,finishing:false};
    try{
      for(const item of selected){
        const target=new BrowserWindow({...item.display.bounds,show:false,frame:false,thickFrame:false,fullscreen:true,transparent:false,backgroundColor:'#111827',alwaysOnTop:true,skipTaskbar:true,resizable:false,movable:false,hasShadow:false,enableLargerThanScreen:true,webPreferences:prefs(path.join(__dirname,'capture/preload.cjs'))});
        secureWindow(target,overlayPath);target.setAlwaysOnTop(true,'screen-saver');target.setMenu(null);
        captureSession.windows.set(target.webContents.id,{...item,window:target});
        target.on('closed',()=>{if(captureSession&&!captureSession.finishing)finishCapture(null);});
        target.webContents.on('did-fail-load',()=>finishCapture(null));
        target.once('ready-to-show',()=>{if(captureSession&&!target.isDestroyed()){target.setBounds(item.display.bounds);target.show();target.focus();}});
        void target.loadFile(overlayPath);
      }
    }catch{finishCapture(null);reject(new UserError('无法显示框选层，请重试。'));}
  });
}
function cancelCapture(){captureGeneration++;finishCapture(null);}
function finishCapture(png){
  const current=captureSession;if(!current||current.finishing)return;
  current.finishing=true;captureSession=null;
  for(const item of current.windows.values())if(!item.window.isDestroyed())item.window.destroy();
  current.windows.clear();current.resolve(png);if(!quitting)showPanel();
}
app.on('before-quit',()=>{quitting=true;clearTimeout(smokeTimer);controller?.invalidate();finishCapture(null);globalShortcut.unregisterAll();tray?.destroy();});
app.on('window-all-closed',()=>{/* Tray lifecycle owns application shutdown. */});
app.on('activate',()=>showPanel());
