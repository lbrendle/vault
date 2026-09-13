import {renderFragment} from './markdown';
import {api,assetURL} from './api';
// Resolve attachments and diagrams only when their section approaches the reader.
export function enhanceReader(root,path){
 let cancelled=false,running=0;const waiting=[],jobs=new Set();
 const observer=new IntersectionObserver(entries=>{for(const entry of entries)if(entry.isIntersecting){observer.unobserve(entry.target);waiting.push(entry.target)}pump()},{root:root.closest('.reader-scroll')?.closest('.chat-turn')?root.closest('.chat-scroll'):root.closest('.reader-scroll'),rootMargin:'600px'});
 async function run(item){try{
  if(item.classList.contains('mermaid')){const {default:mermaid}=await import('mermaid');if(cancelled||!item.isConnected)return;mermaid.initialize({startOnLoad:false,theme:document.documentElement.dataset.mode==='dark'?'dark':'default',securityLevel:'strict'});await mermaid.run({nodes:[item]});return}
  const target=item.dataset.wiki||item.dataset.image,rows=await api('resolve',{target,path});if(cancelled||!item.isConnected)return;if(rows.length!==1){item.textContent='Unresolved embed: '+target;return}const doc=rows[0];
  if(['png','jpg','jpeg','gif','svg','webp','heic'].includes(doc.ext)){const img=document.createElement('img');img.src=assetURL(doc.path);img.alt=doc.title;img.loading='lazy';item.replaceWith(img)}
  else if(['md','markdown'].includes(doc.ext)){const data=await api('read',{path:doc.path});if(cancelled||!item.isConnected)return;const box=document.createElement('section');box.className='embedded-note';box.append(renderFragment(data.content.slice(0,30000)));item.replaceWith(box)}
  else{item.textContent='↗ '+doc.title;item.dataset.wiki=doc.path;item.className='wikilink attachment-link'}
 }catch{if(!cancelled)item.textContent='Attachment unavailable'}finally{running--;pump()}}
 function pump(){while(!cancelled&&running<2&&waiting.length){running++;run(waiting.shift())}}
 for(const item of root.querySelectorAll('[data-embed],[data-image],.mermaid'))if(!jobs.has(item)){jobs.add(item);observer.observe(item)}
 return()=>{cancelled=true;observer.disconnect();waiting.length=0};
}
