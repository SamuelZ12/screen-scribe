'use strict';
const {spawn}=require('node:child_process');
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const executable=require('electron'),root=path.resolve(__dirname,'..');
const child=spawn(executable,[root,'--smoke-test'],{cwd:root,env:{...process.env},stdio:['ignore','pipe','pipe']});
let output='',errors='',timedOut=false;
child.stdout.on('data',value=>{output+=value.toString();if(output.length>100000)child.kill();});
child.stderr.on('data',value=>{errors=(errors+value.toString()).slice(-10000);});
const deadline=setTimeout(()=>{timedOut=true;child.kill();},25000);
child.on('error',()=>{clearTimeout(deadline);console.error('Electron smoke process could not start');process.exitCode=1;});
child.on('exit',code=>{
 clearTimeout(deadline);
 try{fs.rmSync(path.join(os.tmpdir(),`ScreenScribe-Windows-Smoke-${child.pid}`),{recursive:true,force:true});}catch{}
 let report;
 for(const line of output.split(/\r?\n/)){try{const parsed=JSON.parse(line);if(parsed.rendererBridge===true)report=parsed;}catch{}}
 const valid=!timedOut&&code===0&&report?.ok===true&&report.demo===true&&report.version===require('../package.json').version;
 if(valid){fs.mkdirSync(path.join(root,'artifacts'),{recursive:true});fs.writeFileSync(path.join(root,'artifacts/renderer-smoke.json'),JSON.stringify({...report,checkedAt:new Date().toISOString(),windowsRuntimeVerified:report.platform==='win32'},null,2)+'\n');console.log(JSON.stringify(report));}
 else{console.error('Renderer smoke failed: required IPC proof was not returned.');if(errors)console.error(errors);process.exitCode=1;}
});
