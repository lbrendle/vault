const clamp=(min,max,value)=>Math.max(min,Math.min(max,value));
// Distances grow linearly with camera zoom; symbols and text grow more slowly,
// so every zoom step creates more readable space instead of enlarging clutter.
export function graphMetrics(zoom){return {nodeDiameter:clamp(2.4,6.5,2.4+1.3*Math.log2(1+zoom)),fontSize:clamp(12,17,13+1.4*Math.log2(Math.max(.5,zoom))),labelOpacity:clamp(0,1,(zoom-.22)/.5)}}
export function placeGraphLabels(points,{width,height,fontSize,measure,top=80,bottom=75,maxTextWidth=250}){
 const cell=32,grid=new Map(),labels=[],heightPx=Math.ceil(fontSize+12);
 const keys=r=>{const keys=[];for(let x=Math.floor(r.x/cell);x<=Math.floor((r.x+r.w)/cell);x++)for(let y=Math.floor(r.y/cell);y<=Math.floor((r.y+r.h)/cell);y++)keys.push(x+':'+y);return keys};
 const add=r=>{for(const key of keys(r)){if(!grid.has(key))grid.set(key,[]);grid.get(key).push(r)}};
 const overlaps=(a,b)=>a.x<b.x+b.w&&a.x+a.w>b.x&&a.y<b.y+b.h&&a.y+a.h>b.y;
 const free=r=>r.x>=12&&r.y>=top&&r.x+r.w<=width-12&&r.y+r.h<=height-bottom&&!keys(r).some(key=>grid.get(key)?.some(other=>overlaps(r,other)));
 // Reserve the dots first, so no title can be printed through another node.
 for(const p of points)if(p.x>=-12&&p.x<=width+12&&p.y>=-12&&p.y<=height+12){const r=p.radius+4;add({x:p.x-r,y:p.y-r,w:r*2,h:r*2})}
 for(const p of [...points].sort((a,b)=>(b.priority||0)-(a.priority||0)||(b.degree||0)-(a.degree||0)||a.index-b.index)){
  if(!p.label)continue;let text=p.label;
  if(measure(text)>maxTextWidth){let lo=0,hi=text.length;while(lo<hi){const mid=Math.ceil((lo+hi)/2);if(measure(text.slice(0,mid)+'…')<=maxTextWidth)lo=mid;else hi=mid-1}text=text.slice(0,lo)+'…'}
  const w=Math.ceil(measure(text))+12,gap=p.radius+9;
  const candidates=[{x:p.x+gap,y:p.y-heightPx/2},{x:p.x-gap-w,y:p.y-heightPx/2},{x:p.x-w/2,y:p.y+gap},{x:p.x-w/2,y:p.y-gap-heightPx}];
  for(const candidate of candidates){const rect={...candidate,w,h:heightPx};if(!free(rect))continue;labels.push({...rect,text,index:p.index,priority:p.priority||0});add({x:rect.x-5,y:rect.y-4,w:rect.w+10,h:rect.h+8});break}
 }
 return labels;
}
