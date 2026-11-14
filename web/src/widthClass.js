// The window changes width while the app is running: a folding iPhone opens and
// closes, a phone rotates, an iPad window is resized. Layout follows the current
// width, never the device model, and never a width sampled once at launch.

// At this width or narrower the workspace shows one pane at a time. It must match
// the max-width of the one-pane media queries in workspace.css, glass.css and
// reader.css; widthClass.test.js checks that they agree.
export const PHONE_MAX=650;
export const isPhoneWidth=(width=innerWidth)=>width<=PHONE_MAX;

// Calls changed(narrow) each time the window crosses `limit`: true when it becomes
// `limit` wide or narrower, false when it becomes wider. Returns the cleanup.
export function onWidthCrossing(limit,changed,target=window){
 let narrow=target.innerWidth<=limit;
 const resize=()=>{const next=target.innerWidth<=limit;if(next!==narrow){narrow=next;changed(next)}};
 target.addEventListener('resize',resize);
 return()=>target.removeEventListener('resize',resize);
}
