import React,{useEffect,useRef,useState} from 'react';
import {renderFragment,markdownFragment} from './markdown';
import {api} from './api';
import {enhanceReader} from './readerEnhancements';
import MarkdownWorker from './markdown.worker.js?worker&inline';
const sectionHeight=(section,width)=>Math.max(120,Math.ceil(section.characters/Math.max(28,width/8))*25+section.headings.length*35);
export default function Reader({content='',path,onLink,anchor,onTaskToggle}){
 const lastPath=useRef(),host=useRef(),pane=useRef(),jump=useRef(()=>{}),callbacks=useRef({onLink,onTaskToggle}),[formatting,setFormatting]=useState(false),[error,setError]=useState('');callbacks.current={onLink,onTaskToggle};
 useEffect(()=>{
  const el=host.current;if(!el)return;let cancelled=false,worker,observer,resizeObserver,cleanup=[],sections=[],pending=new Set(),mounted=new Map(),visible=new Set(),targetAnchor=anchor,printing=false,prepared=false,formatError,printResolve,printReject;
  if(lastPath.current!==path){pane.current.scrollTop=0;lastPath.current=path}
  const restorePrint=()=>{printing=false;visible.clear();for(const box of el.children)observer?.observe(box)};
  const finishPrint=()=>{if(printing&&mounted.size===sections.length&&printResolve){printResolve(restorePrint);printResolve=null}};
  pane.current.preparePrint=()=>content.length<=80000?Promise.resolve(()=>{}):new Promise((resolve,reject)=>{if(formatError){reject(formatError);return}printing=true;printResolve=resolve;printReject=reject;observer?.disconnect();if(prepared){sections.forEach((_,index)=>request(index));finishPrint()}});
  const within=target=>{if(target)pane.current.scrollTo({top:pane.current.scrollTop+target.getBoundingClientRect().top-pane.current.getBoundingClientRect().top-20,behavior:'instant'})};
  const findAnchor=value=>[...el.querySelectorAll('[id]')].find(e=>e.id===decodeURIComponent(value));
  const request=index=>{if(!worker||pending.has(index)||mounted.has(index))return;pending.add(index);worker.postMessage({kind:'render',index})};
  jump.current=value=>{targetAnchor=value;if(!value)return;const found=findAnchor(value);if(found){within(found);targetAnchor=null;return}const index=sections.findIndex(s=>s.headings.includes(decodeURIComponent(value)));if(index>=0){within(el.children[index]);request(index)}};
  const click=e=>{const task=e.target.closest('input[data-task]');if(task){if(!task.closest('.embedded-note')&&callbacks.current.onTaskToggle)callbacks.current.onTaskToggle(Number(task.dataset.task),task.checked);else task.checked=!task.checked;return}const a=e.target.closest('a,[data-wiki]');if(!a)return;e.preventDefault();if(a.dataset.wiki){callbacks.current.onLink?.(a.dataset.wiki);return}const href=a.getAttribute('href');if(href?.startsWith('#'))jump.current(href.slice(1));else if(/^https?:|^mailto:/i.test(href||''))api('openExternal',{url:href});else if(href)callbacks.current.onLink?.(href)};
  el.addEventListener('click',click);setError('');setFormatting(content.length>80000);
  // A short first-screen preview appears before a large document is parsed.
  el.replaceChildren(renderFragment(content.length>80000?content.slice(0,12000):content));
  if(content.length<=80000){cleanup.push(enhanceReader(el,path));jump.current(anchor)}else{
   worker=new MarkdownWorker();
   worker.onmessage=({data})=>{if(cancelled)return;
    if(data.kind==='error'){setError('Could not finish formatting. The complete file is available in Source mode.');setFormatting(false);formatError=new Error(data.message);printReject?.(formatError);return}
    if(data.kind==='prepared'){
     prepared=true;sections=data.sections;const fragment=document.createDocumentFragment();const width=el.clientWidth-80;
     sections.forEach((section,index)=>{const box=document.createElement('section');box.className='markdown-section';box.dataset.section=String(index);box.style.minHeight=sectionHeight(section,width)+'px';box.setAttribute('aria-label',section.headings[0]||`Document section ${index+1}`);fragment.append(box)});
     el.replaceChildren(fragment);observer=new IntersectionObserver(entries=>{for(const entry of entries){const index=Number(entry.target.dataset.section);if(entry.isIntersecting){visible.add(index);request(index)}else visible.delete(index)}
      // Keep nearby sections, releasing distant DOM while preserving its height.
      for(const [index,dispose] of mounted)if(!printing&&!visible.has(index)){const box=el.children[index];box.style.minHeight=box.getBoundingClientRect().height+'px';dispose();box.replaceChildren();box.removeAttribute('data-ready');mounted.delete(index)}
     },{root:pane.current.closest('.chat-turn')?pane.current.closest('.chat-scroll'):pane.current,rootMargin:'1000px'});
     if(printing){sections.forEach((_,index)=>request(index));finishPrint()}else{for(const box of el.children)observer.observe(box);if(sections.length)request(0);else setFormatting(false);jump.current(targetAnchor)}
     let previousWidth=el.clientWidth;resizeObserver=new ResizeObserver(()=>{if(Math.abs(el.clientWidth-previousWidth)<1)return;previousWidth=el.clientWidth;sections.forEach((section,index)=>{if(!mounted.has(index))el.children[index].style.minHeight=sectionHeight(section,previousWidth-80)+'px'})});resizeObserver.observe(el);
    }
    if(data.kind==='section'){
     pending.delete(data.index);const box=el.children[data.index];if(!box)return;box.replaceChildren(markdownFragment(data.html));box.style.minHeight='0';box.dataset.ready='true';mounted.set(data.index,enhanceReader(box,path));setFormatting(false);
     if(targetAnchor){const found=findAnchor(targetAnchor);if(found){within(found);targetAnchor=null}}finishPrint();
    }
   };
   worker.onerror=()=>{if(!cancelled){setError('Could not finish formatting. The complete file is available in Source mode.');setFormatting(false);formatError=new Error('Document formatting failed');printReject?.(formatError)}};
   worker.postMessage({kind:'prepare',content});
  }
  return()=>{cancelled=true;printReject?.(new Error('Document closed'));delete pane.current?.preparePrint;worker?.terminate();observer?.disconnect();resizeObserver?.disconnect();cleanup.forEach(dispose=>dispose());mounted.forEach(dispose=>dispose());el.removeEventListener('click',click);jump.current=()=>{}};
 },[content,path]);
 useEffect(()=>{jump.current(anchor)},[anchor]);
 return <div key={path} ref={pane} className="reader-scroll"><article ref={host} className="prose"/>{formatting&&<div className="reader-progress" role="status">Opening the rest of this document…</div>}{error&&<p className="reader-error" role="alert">{error}</p>}</div>;
}

export async function prepareReaderForPrint(){const pane=document.querySelector('.document-body > .reader-scroll');return pane?.preparePrint?pane.preparePrint():()=>{}}
