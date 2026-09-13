// WebKit's visual viewport is the area above the software keyboard. Keep a single
// owner for keyboard resizing instead of combining native and CSS avoidance.
export function installViewport(){
 if(window.__nativeKeyboardLayout){document.documentElement.dataset.nativeKeyboard='true';return;}
 const root=document.documentElement,viewport=window.visualViewport;
 const resize=()=>{if(!viewport)return;root.style.setProperty('--window-height',`${Math.round(viewport.height)}px`);root.style.setProperty('--window-top',`${Math.round(viewport.offsetTop)}px`);root.dataset.keyboard=innerHeight-viewport.height>140?'open':'closed'};
 viewport?.addEventListener('resize',resize);viewport?.addEventListener('scroll',resize);window.addEventListener('resize',resize);resize();
}
