// Preserve edits that have not reached the debounced native save yet.
export function mergeIncomingState(local,incoming){
 // A departing workspace can emit a final sync event while the next one loads.
 // It must neither dereference null nor populate the new workspace with old chats.
 if(!local||!incoming)return local;
 const chats=new Map((incoming.chats||[]).map(c=>[c.id,c]));
 for(const c of local.chats||[])if(!chats.has(c.id)||(c.updated||0)>=(chats.get(c.id).updated||0))chats.set(c.id,c);
 const changes={...(incoming.bookmarkChanges||{})};
 for(const [path,change] of Object.entries(local.bookmarkChanges||{}))if(!changes[path]||change.modified>=changes[path].modified)changes[path]=change;
 const bookmarks=new Set([...(local.bookmarks||[]),...(incoming.bookmarks||[])]);
 for(const [path,change] of Object.entries(changes))change.present?bookmarks.add(path):bookmarks.delete(path);
 return {...local,chats:[...chats.values()].sort((a,b)=>(b.updated||0)-(a.updated||0)),bookmarks:[...bookmarks],bookmarkChanges:changes};
}
