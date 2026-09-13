import test from 'node:test';
import assert from 'node:assert/strict';
import {FileBrowser} from './fileBrowser.js';
const rows=(start,count)=>Array.from({length:count},(_,i)=>({path:`note-${start+i}.md`,directory:false}));
test('sync refresh preserves loaded pages and stops at the last page',async()=>{
 const files=rows(0,425);let view;
 const browser=new FileBrowser(async({offset})=>files.slice(offset,offset+200),next=>view=next,assert.fail);
 await browser.reset('notes');await browser.loadMore();assert.equal(view.rows.length,400);
 files[0]={...files[0],title:'Changed by another device'};await browser.refresh();
 assert.equal(view.rows.length,400);assert.equal(view.rows[0].title,'Changed by another device');
 await browser.loadMore();assert.equal(view.rows.length,425);assert.equal(view.more,false);
 await browser.loadMore();assert.equal(view.rows.length,425);
});
test('late folder and pagination replies cannot enter another workspace',async()=>{
 const waiting=[];let view;
 const browser=new FileBrowser(args=>new Promise(resolve=>waiting.push({args,resolve})),next=>view=next,assert.fail);
 const first=browser.reset('old');waiting.shift().resolve(rows(0,200));await first;
 const more=browser.loadMore();const old=waiting.splice(0);
 const next=browser.reset('new');waiting.shift().resolve([{path:'new.md'}]);await next;
 for(const request of old)request.resolve(rows(request.args.offset,200));await more;
 assert.deepEqual(view.rows,[{path:'new.md'}]);assert.equal(view.busy,false);
});
test('a newer refresh wins over a slower earlier refresh',async()=>{
 const waiting=[];let view;
 const browser=new FileBrowser(()=>new Promise(resolve=>waiting.push(resolve)),next=>view=next,assert.fail);
 const first=browser.reset('');const second=browser.refresh();waiting[1]([{path:'latest.md'}]);await second;
 waiting[0]([{path:'stale.md'}]);await first;assert.equal(view.rows[0].path,'latest.md');
});
