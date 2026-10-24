'use strict';
// Overlay coordinates are display-local DIP. Thumbnail dimensions are measured,
// never inferred from DPI or monitor ordering (mixed scaling/negative origins).
function cropRect(selection, bounds, imageSize) {
  if(!selection||!bounds||!imageSize) throw new Error('选区无效。');
  for(const value of [selection.x,selection.y,selection.width,selection.height,bounds.width,bounds.height,imageSize.width,imageSize.height]) {
    if(typeof value!=='number'||!Number.isFinite(value)) throw new Error('选区无效。');
  }
  if(bounds.width<=0||bounds.height<=0||imageSize.width<=0||imageSize.height<=0||selection.width<2||selection.height<2) throw new Error('请框选至少 2×2 的区域。');
  const clamp=(n,max)=>Math.max(0,Math.min(max,n));
  const left=clamp(selection.x,bounds.width),top=clamp(selection.y,bounds.height);
  const right=clamp(selection.x+selection.width,bounds.width),bottom=clamp(selection.y+selection.height,bounds.height);
  const x=Math.floor(left*imageSize.width/bounds.width),y=Math.floor(top*imageSize.height/bounds.height);
  const r=Math.ceil(right*imageSize.width/bounds.width),b=Math.ceil(bottom*imageSize.height/bounds.height);
  if(r-x<2||b-y<2) throw new Error('选区过小或超出屏幕。');
  return {x,y,width:r-x,height:b-y};
}
function panelPosition(trayBounds, display, size={width:716,height:524}) {
  const area=display.workArea;
  const clamp=(n,min,max)=>Math.max(min,Math.min(max,n));
  const width=Math.min(size.width,area.width),height=Math.min(size.height,area.height);
  return {width,height,x:Math.round(clamp(trayBounds.x+trayBounds.width-width,area.x,area.x+area.width-width)),y:Math.round(clamp(trayBounds.y-height-8,area.y,area.y+area.height-height))};
}
module.exports={cropRect,panelPosition};
