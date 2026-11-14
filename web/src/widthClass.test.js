import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {PHONE_MAX,isPhoneWidth,onWidthCrossing} from './widthClass.js';
import {applyFold,installFold} from './fold.js';

function fakeWindow(innerWidth){
 const listeners=new Map();
 return {innerWidth,listeners,
  addEventListener:(name,fn)=>listeners.set(name,fn),removeEventListener:name=>listeners.delete(name),
  resizeTo(width){this.innerWidth=width;listeners.get('resize')?.()},
  dispatch(name,detail){listeners.get(name)?.({detail})}};
}
function fakeRoot(){
 const properties=new Map();
 return {dataset:{},properties,style:{setProperty:(name,value)=>properties.set(name,value),removeProperty:name=>properties.delete(name)}};
}

test('a closed folding phone is one pane and its open display is not',()=>{
 assert.equal(isPhoneWidth(466),true);
 assert.equal(isPhoneWidth(PHONE_MAX),true);
 assert.equal(isPhoneWidth(PHONE_MAX+1),false);
 assert.equal(isPhoneWidth(669),false);
});

test('the one-pane media queries use the same width as the script',()=>{
 for(const file of ['workspace.css','glass.css','reader.css']){
  const css=fs.readFileSync(new URL(file,import.meta.url),'utf8');
  const widths=[...css.matchAll(/@media\s*\(max-width:\s*(\d+)px\)/g)].map(match=>Number(match[1]));
  assert.ok(widths.includes(PHONE_MAX),`${file} has no ${PHONE_MAX}px query`);
  assert.ok(!widths.some(width=>width!==PHONE_MAX&&Math.abs(width-PHONE_MAX)<=60),`${file} has a second query near ${PHONE_MAX}px`);
 }
});

test('crossing the width reports once per direction and stops after cleanup',()=>{
 const target=fakeWindow(669),seen=[];
 const stop=onWidthCrossing(PHONE_MAX,narrow=>seen.push(narrow),target);
 target.resizeTo(700);target.resizeTo(951);
 assert.deepEqual(seen,[]);
 target.resizeTo(466);target.resizeTo(430);
 assert.deepEqual(seen,[true]);
 target.resizeTo(669);
 assert.deepEqual(seen,[true,false]);
 stop();target.resizeTo(466);
 assert.deepEqual(seen,[true,false]);
});

test('a bent display publishes its axis and position',()=>{
 const root=fakeRoot();
 assert.equal(applyFold({axis:'vertical',start:322.4,size:24},root),'vertical');
 assert.equal(root.dataset.fold,'vertical');
 assert.equal(root.properties.get('--fold-start'),'322px');
 assert.equal(root.properties.get('--fold-size'),'24px');
});

test('a flat or unknown report clears the fold',()=>{
 for(const flat of [null,undefined,{},{axis:'vertical',start:334,size:0},{axis:'diagonal',start:10,size:10},{axis:'horizontal',start:NaN,size:20}]){
  const root=fakeRoot();applyFold({axis:'horizontal',start:320,size:28},root);
  assert.equal(applyFold(flat,root),null);
  assert.equal('fold' in root.dataset,false);
  assert.equal(root.properties.size,0);
 }
});

test('the page asks for the current fold and then follows events',async()=>{
 const target=fakeWindow(669),root=fakeRoot(),asked=[];
 const original=globalThis.document;globalThis.document={documentElement:root};
 try{
  const stop=installFold(async method=>{asked.push(method);return {axis:'vertical',start:322,size:24}},target);
  await new Promise(resolve=>setTimeout(resolve,0));
  assert.deepEqual(asked,['fold']);
  assert.equal(root.dataset.fold,'vertical');
  target.dispatch('vault-event',{name:'files',data:{paths:[]}});
  assert.equal(root.dataset.fold,'vertical');
  target.dispatch('vault-event',{name:'fold',data:{}});
  assert.equal('fold' in root.dataset,false);
  stop();
  assert.equal(target.listeners.has('vault-event'),false);
  installFold(async()=>{throw new Error('Unknown action: fold')},target);
  await new Promise(resolve=>setTimeout(resolve,0));
  assert.equal('fold' in root.dataset,false);
 }finally{globalThis.document=original}
});
