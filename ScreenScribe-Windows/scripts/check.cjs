'use strict';
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..');let checked=0;
function walk(folder){for(const item of fs.readdirSync(folder,{withFileTypes:true})){const file=path.join(folder,item.name);if(item.isDirectory())walk(file);else if(/\.(?:cjs|js)$/.test(item.name)){const r=spawnSync(process.execPath,['--check',file],{encoding:'utf8'});if(r.status!==0){process.stderr.write(r.stderr);process.exit(1);}checked++;}}}
for(const folder of ['src','scripts','tests'])walk(path.join(root,folder));
const manifest=JSON.parse(fs.readFileSync(path.join(root,'package.json'),'utf8'));
for(const name of ['assets/icon.png','assets/tray.png','assets/test-equation.png','build-resources/icon.ico','assets/vendor/katex.min.js','assets/vendor/katex.min.css','assets/vendor/LICENSE-KaTeX.txt','docs/使用说明.txt','LICENSE','THIRD-PARTY-NOTICES.md'])if(!fs.existsSync(path.join(root,name)))throw new Error('Missing build input: '+name);
if(manifest.build.win.requestedExecutionLevel!=='asInvoker'||manifest.build.nsis.perMachine||manifest.build.nsis.allowElevation)throw new Error('Installer must remain per-user/asInvoker.');
console.log(JSON.stringify({ok:true,syntaxFiles:checked,version:manifest.version,installScope:'current-user'}));
