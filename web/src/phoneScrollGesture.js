// iPhone-only gesture ownership. The final position matters even if WebKit
// coalesces every intermediate move; a swipe must never activate its first row.
export function attachTouchScroll(element,{
 enabled=()=>document.documentElement.dataset.device==='phone',
 now=()=>performance.now(),requestFrame=requestAnimationFrame,cancelFrame=cancelAnimationFrame,
}={}){
 let gesture=null,frame=0,suppressUntil=0,activatingTap=false;
  const stop=()=>{cancelFrame(frame);frame=0};
  const clamp=value=>Math.max(0,Math.min(element.scrollHeight-element.clientHeight,value));
  const coast=velocity=>{
   let previous=now();
   const tick=time=>{const dt=Math.min(time-previous,32);previous=time;const before=element.scrollTop;const after=clamp(before+velocity*dt);element.scrollTop=after;velocity*=Math.exp(-dt/180);if(Math.abs(velocity)>.025&&Math.abs(after-before)>.1)frame=requestFrame(tick);else frame=0};
   frame=requestFrame(tick);
  };
  const down=event=>{
   if(!enabled()||event.pointerType!=='touch'||!event.isPrimary)return;
   const wasCoasting=frame!==0;stop();const target=event.target.closest('button');
   gesture={id:event.pointerId,startX:event.clientX,startY:event.clientY,y:event.clientY,time:event.timeStamp,began:event.timeStamp,moved:wasCoasting,velocity:0,target};
   element.setPointerCapture(event.pointerId);event.preventDefault();
  };
  const move=event=>{
   if(!gesture||event.pointerId!==gesture.id)return;
   const dy=gesture.y-event.clientY,dt=Math.max(8,event.timeStamp-gesture.time);
   if(Math.hypot(event.clientX-gesture.startX,event.clientY-gesture.startY)>7)gesture.moved=true;
   if(gesture.moved){element.scrollTop=clamp(element.scrollTop+dy);gesture.velocity=.6*Math.max(-3,Math.min(3,dy/dt))+.4*gesture.velocity;}
   gesture.y=event.clientY;gesture.time=event.timeStamp;event.preventDefault();
  };
  const finish=event=>{
   if(!gesture||event.pointerId!==gesture.id)return;
   if(event.type==='pointerup')move(event);
   const current=gesture;gesture=null;suppressUntil=now()+700;
   if(element.hasPointerCapture(event.pointerId))element.releasePointerCapture(event.pointerId);
   event.preventDefault();
   if(event.type==='pointerup'){
    if(current.moved){if(event.timeStamp-current.time<100)coast(current.velocity)}
    else if(event.timeStamp-current.began<650&&current.target?.isConnected&&!current.target.disabled){activatingTap=true;try{current.target.click()}finally{activatingTap=false}}
   }
  };
  const click=event=>{if(enabled()&&!activatingTap&&(gesture||frame||now()<suppressUntil)){event.preventDefault();event.stopImmediatePropagation();}};
  element.addEventListener('pointerdown',down);
  element.addEventListener('pointermove',move);
  element.addEventListener('pointerup',finish);
  element.addEventListener('pointercancel',finish);
  element.addEventListener('click',click,true);
  return()=>{stop();element.removeEventListener('pointerdown',down);element.removeEventListener('pointermove',move);element.removeEventListener('pointerup',finish);element.removeEventListener('pointercancel',finish);element.removeEventListener('click',click,true)};
}
