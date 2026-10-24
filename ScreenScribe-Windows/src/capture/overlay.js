'use strict';
let origin=null,dragging=false,finishing=false;
const selection=document.getElementById('selection'),dimensions=document.getElementById('dimensions');
function rect(event){const x=Math.max(0,Math.min(innerWidth,event.clientX)),y=Math.max(0,Math.min(innerHeight,event.clientY));return{x:Math.min(origin.x,x),y:Math.min(origin.y,y),width:Math.abs(origin.x-x),height:Math.abs(origin.y-y)};}
function show(r){selection.hidden=false;Object.assign(selection.style,{left:`${r.x}px`,top:`${r.y}px`,width:`${r.width}px`,height:`${r.height}px`});dimensions.textContent=`${Math.round(r.width)} × ${Math.round(r.height)}`;}
window.captureBridge.getState().then(state=>{document.getElementById('desktop').src=state.imageDataUrl;}).catch(()=>{document.getElementById('error').textContent='无法读取屏幕底图，请按 Esc 取消后重试。';});
window.addEventListener('pointerdown',event=>{if(event.button!==0||finishing)return;origin={x:event.clientX,y:event.clientY};dragging=true;document.body.classList.add('selecting');show(rect(event));document.body.setPointerCapture(event.pointerId);});
window.addEventListener('pointermove',event=>{if(dragging)show(rect(event));});
window.addEventListener('pointerup',async event=>{if(!dragging||finishing)return;dragging=false;const r=rect(event);if(r.width<2||r.height<2){selection.hidden=true;document.body.classList.remove('selecting');return;}finishing=true;await window.captureBridge.finish(r);});
window.addEventListener('keydown',event=>{if(event.key==='Escape'){event.preventDefault();window.captureBridge.cancel();}});
window.addEventListener('contextmenu',event=>{event.preventDefault();window.captureBridge.cancel();});
