import test from 'node:test';import assert from 'node:assert/strict';import {chooseModel} from './modelSelection.js';
const models=[{id:'quick'},{id:'capable',recommended:true}];
test('removing the selected model falls back to an available recommendation',()=>assert.equal(chooseModel(models,['removed']), 'capable'));
test('an explicit available selection takes precedence over a recommendation',()=>assert.equal(chooseModel(models,['quick']),'quick'));
