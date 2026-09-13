import test from 'node:test';
import assert from 'node:assert/strict';
import {attachTouchScroll} from './phoneScrollGesture.js';
function setup(enabled=true){
 const listeners=new Map();let clicks=0,captured=false;
 const target={isConnected:true,disabled:false,click(){clicks++}};
 const element={scrollTop:0,scrollHeight:1600,clientHeight:400,
  addEventListener:(name,fn)=>listeners.set(name,fn),removeEventListener:name=>listeners.delete(name),
  setPointerCapture(){captured=true},hasPointerCapture:()=>captured,releasePointerCapture(){captured=false}};
 let time=1000;
 const clean=attachTouchScroll(element,{enabled:()=>enabled,now:()=>time,requestFrame:()=>1,cancelFrame:()=>{}});
 const send=(type,y,extra={})=>{const e={type,clientX:50,clientY:y,pointerId:1,pointerType:'touch',isPrimary:true,timeStamp:time+=16,target:{closest:()=>target},preventDefault(){this.prevented=true},stopImmediatePropagation(){this.stopped=true},...extra};listeners.get(type)?.(e);return e};
 return {element,send,clean,listeners,clicks:()=>clicks};
}
test('a coalesced swipe scrolls from the final position and never opens the starting row',()=>{
 const s=setup();s.send('pointerdown',350);s.send('pointerup',100);
 assert.equal(s.element.scrollTop,250);assert.equal(s.clicks(),0);
 const click=s.send('click',100,{isTrusted:true});assert.equal(click.prevented,true);assert.equal(click.stopped,true);s.clean();
});
test('a tap activates exactly once while its compatibility click is suppressed',()=>{
 const s=setup();s.send('pointerdown',350);s.send('pointerup',348);
 assert.equal(s.clicks(),1);assert.equal(s.element.scrollTop,0);
 assert.equal(s.send('click',348,{isTrusted:true}).prevented,true);s.clean();
});
test('scroll clamps to its bounds and cancelled gestures never activate',()=>{
 const s=setup();s.send('pointerdown',350);s.send('pointermove',-2000);s.send('pointerup',-2000);
 assert.equal(s.element.scrollTop,1200);assert.equal(s.clicks(),0);
 s.send('pointerdown',100);s.send('pointercancel',100);assert.equal(s.clicks(),0);s.clean();
});
test('iPad gestures and mouse input retain native browser behavior',()=>{
 const pad=setup(false);assert.equal(pad.send('pointerdown',350).prevented,undefined);pad.send('pointerup',100);assert.equal(pad.element.scrollTop,0);assert.equal(pad.clicks(),0);pad.clean();
 const mouse=setup();assert.equal(mouse.send('pointerdown',350,{pointerType:'mouse'}).prevented,undefined);mouse.clean();assert.equal(mouse.listeners.size,0);
});

test('compatibility clicks cannot select a row during a drag, even when untrusted',()=>{
 const s=setup();s.send('pointerdown',350);s.send('pointermove',220);
 assert.equal(s.send('click',220,{isTrusted:false}).prevented,true);
 s.send('pointerup',180);assert.equal(s.send('click',180,{isTrusted:false}).prevented,true);assert.equal(s.clicks(),0);s.clean();
});
test('a tap stops momentum without opening the row underneath it',()=>{
 const s=setup();s.send('pointerdown',350);s.send('pointerup',150);
 s.send('pointerdown',200);s.send('pointerup',200);assert.equal(s.clicks(),0);s.clean();
});
