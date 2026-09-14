import test from 'node:test';
import assert from 'node:assert/strict';
import {parseNotebook,serializeNotebook,applyCellResult} from './labNotebook.js';
test('Jupyter round trip retains attachments, metadata, outputs and raw cells',()=>{
 const original={nbformat:4,nbformat_minor:5,metadata:{kernelspec:{name:'python3'},custom:{source:'curriculum'}},cells:[{id:'m',cell_type:'markdown',metadata:{tags:['reading']},source:['# Question\n','Why?'],attachments:{image:{'image/png':'AA'}}},{id:'code',cell_type:'code',source:['a = 2\n','a'],metadata:{tags:['exercise']},execution_count:5,outputs:[{output_type:'execute_result',execution_count:5,data:{'text/plain':'2'},metadata:{}}]},{id:'raw',cell_type:'raw',source:[],metadata:{format:'text/plain'}}]};
 assert.deepEqual(JSON.parse(serializeNotebook(parseNotebook(JSON.stringify(original)))),original);
});
test('execution changes only selected cell while preserving author metadata',()=>{
 const nb=parseNotebook(JSON.stringify({nbformat:4,cells:[{id:'x',cell_type:'code',metadata:{tags:['graded']},source:'1',outputs:[]},{id:'y',cell_type:'markdown',source:'Text',metadata:{}}]}));
 const result={id:'run-1',seconds:0.25,status:'error',outputs:[{output_type:'error',ename:'ValueError',evalue:'fixture',traceback:[]}]};
 const next=applyCellResult(nb,'x',result,1);assert.equal(next.cells[1],nb.cells[1]);assert.deepEqual(next.cells[0].metadata.tags,['graded']);assert.equal(next.cells[0].metadata.vault.status,'error');assert.deepEqual(next.cells[0].outputs,result.outputs);assert.equal(nb.cells[0].outputs.length,0);
});
test('unsupported notebook format is rejected without rewriting',()=>assert.throws(()=>parseNotebook('{"nbformat":3,"worksheets":[]}'),/version 4/));
