import test from 'node:test';import assert from 'node:assert/strict';import {matches,baseFolder,parseBase} from './base.js';
test('Investor Base folder, filters and dates',()=>{
 const base=parseBase('filters:\n  and:\n    - file.inFolder("Fundraising/Investors")\n    - type == "archii-investor"\n');
 assert.equal(baseFolder(base,''),'Fundraising/Investors');
 const row={path:'Fundraising/Investors/Example.md',properties:{type:'archii-investor',priority:'P1',next_action_date:'2020-01-01',status:'Research'}};
 assert.equal(matches(base.filters,row),true);assert.equal(matches('priority == "Watch"',row),false);
 assert.equal(matches({and:['next_action_date != null','date(next_action_date) <= today()','status != "Passed"']},row),true);
 assert.throws(()=>matches('arbitraryFunction()',row),/Unsupported/);
});
