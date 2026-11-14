// A folding display that is partly closed bends across the middle of the window.
// WebKit does not describe the bend to the page, so the native shell does:
// {axis:'vertical',start,size} for two pages side by side, {axis:'horizontal',...}
// for a top and a bottom half. `start` and `size` are CSS pixels from the window's
// left (vertical) or top (horizontal) edge. Anything else means the display is flat.
// workspace.css reads the result as [data-fold], --fold-start and --fold-size.
export function applyFold(fold,root=document.documentElement){
 const bent=Boolean(fold)&&(fold.axis==='vertical'||fold.axis==='horizontal')&&Number.isFinite(fold.start)&&Number.isFinite(fold.size)&&fold.start>0&&fold.size>0;
 if(!bent){delete root.dataset.fold;root.style.removeProperty('--fold-start');root.style.removeProperty('--fold-size');return null}
 root.dataset.fold=fold.axis;
 root.style.setProperty('--fold-start',Math.round(fold.start)+'px');
 root.style.setProperty('--fold-size',Math.round(fold.size)+'px');
 return fold.axis;
}

// Asks the shell for the current bend, then follows its 'fold' events. Shells
// without a folding display answer with nothing or an error; both mean flat.
export function installFold(api,target=window){
 const listener=event=>{if(event.detail?.name==='fold')applyFold(event.detail.data)};
 target.addEventListener('vault-event',listener);
 Promise.resolve().then(()=>api('fold')).then(fold=>applyFold(fold)).catch(()=>{});
 return()=>target.removeEventListener('vault-event',listener);
}
