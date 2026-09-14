import test from 'node:test';
import assert from 'node:assert/strict';
import {assistantConversation,assistantFileContext,assistantMessages} from './assistantMessages.js';

const reply=text=>({status:'ok',outputs:[{output_type:'stream',name:'stdout',text}]});
test('assistant context follows the chosen project, provider and execution device',()=>{
 const history=[
  {project:'A',provider:'local',target:'This iPad',prompt:'Keep this local',result:reply('Local reply')},
  {project:'B',provider:'codex',target:'Paired Mac',prompt:'Another project',result:reply('Unrelated')},
  {project:'A',provider:'codex',target:'Paired Mac',prompt:'This conversation',result:reply('Relevant')}
 ];
 const selected=assistantConversation(history,'A','codex','Paired Mac');
 const messages=assistantMessages('Continue',selected,null,false);
 assert.deepEqual(messages.map(m=>m.content),['This conversation','Relevant','Continue']);
 assert.equal(assistantMessages('New conversation',[],{path:'secret.py',content:'private'},false)[0].content,'New conversation');
});
test('attaching a notebook includes its source without image outputs or metadata',()=>{
 const file={path:'experiment.ipynb',content:JSON.stringify({metadata:{secret:'hidden metadata'},cells:[{cell_type:'markdown',source:['# Question']},{cell_type:'code',source:['print(42)'],outputs:[{data:{'image/png':'hidden image'}}]}]})};
 const context=assistantFileContext(file);
 assert.match(context,/Question/);assert.match(context,/print\(42\)/);assert.doesNotMatch(context,/hidden/);
 const messages=assistantMessages('Explain',[],file,true);
 assert.match(messages[0].content,/Attached file: experiment.ipynb/);
 assert.equal(assistantMessages('Explain',[],file,false)[0].content,'Explain');
});
test('assistant context is bounded and failed or pending replies are omitted',()=>{
 const history=[{prompt:'broken',result:{status:'error',outputs:[]}},{prompt:'pending',status:'pending'},...Array.from({length:20},()=>({prompt:'q'.repeat(4000),result:reply('a'.repeat(8000))}))];
 const messages=assistantMessages('next',history,{path:'large.py',content:'x'.repeat(100000)},true);
 assert.ok(messages.reduce((n,m)=>n+m.content.length,0)<=12000);
 assert.doesNotMatch(JSON.stringify(messages),/broken|pending/);
 assert.match(messages.at(-1).content,/File excerpt ends here/);
 assert.equal(messages.at(-1).role,'user');
});
