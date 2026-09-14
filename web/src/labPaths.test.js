import test from 'node:test';
import assert from 'node:assert/strict';
import {isLabFile,labTargetForPath,labVaultPath} from './labPaths.js';
test('routes code in its original folder and leaves Markdown in the reader',()=>{
 assert.equal(isLabFile('A practical lab.md'),false);
 assert.equal(isLabFile('V02.markdown'),false);
 assert.equal(isLabFile('Models/model.SWIFT'),true);
 assert.deepEqual(labTargetForPath('Curriculum/Starter Lab/baseline.py'),{project:'@/Curriculum/Starter Lab',path:'baseline.py'});
 assert.deepEqual(labTargetForPath('baseline.py'),{project:'@/',path:'baseline.py'});
 for(const path of ['baseline.py','Curriculum/Starter Lab/baseline.py','Labs/First experiment/nested/hello.py']){
  const t=labTargetForPath(path);assert.equal(labVaultPath(t.project,t.path),path);
 }
 assert.throws(()=>labTargetForPath('../private.py'));
 assert.throws(()=>labTargetForPath('notes.md'));
});
