import test from 'node:test';import assert from 'node:assert/strict';import {splitModelOutput} from './modelOutput.js';
test('Qwen and Gemma reasoning channels do not leak into answers',()=>{
 assert.deepEqual(splitModelOutput('<think>checking</think>60%'),{content:'60%',reasoning:'checking',thinking:false});
 assert.deepEqual(splitModelOutput('<|channel>thought\nchecking<channel|>60%<turn|>'),{content:'60%',reasoning:'checking',thinking:false});
 assert.deepEqual(splitModelOutput('<|channel>thought\nchecking'),{content:'',reasoning:'checking',thinking:true});
 assert.equal(splitModelOutput('60%<|chan').content,'60%');
 assert.equal(splitModelOutput('Plain answer').content,'Plain answer');
});
