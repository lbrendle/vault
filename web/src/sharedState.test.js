import {test} from 'node:test';import assert from 'node:assert/strict';import {mergeIncomingState} from './sharedState.js';
test('incoming sync preserves a newer unsaved streamed answer and bookmark toggle',()=>{const result=mergeIncomingState({activeChat:'a',chats:[{id:'a',updated:30,messages:[{content:'answer still arriving'}]}],bookmarks:[],bookmarkChanges:{note:{present:false,modified:30}}},{chats:[{id:'a',updated:20,messages:[{content:'answer'}]},{id:'b',updated:25,messages:[]}],bookmarks:['note'],bookmarkChanges:{note:{present:true,modified:20}}});assert.equal(result.activeChat,'a');assert.equal(result.chats[0].messages[0].content,'answer still arriving');assert.equal(result.chats.length,2);assert.deepEqual(result.bookmarks,[])});
test('a late sync event cannot populate a workspace that has been cleared for switching',()=>{
 const departing={chats:[{id:'old-workspace',updated:99}],bookmarks:['Private.md']};
 assert.equal(mergeIncomingState(null,departing),null);
 assert.equal(mergeIncomingState(undefined,departing),undefined);
 const fresh={chats:[],bookmarks:[]};assert.equal(mergeIncomingState(fresh,null),fresh);
 assert.deepEqual(mergeIncomingState(fresh,{chats:[],bookmarks:[]}).chats,[]);
});
