import React,{useEffect,useRef,useState} from 'react';
import {ChevronLeft,ChevronRight,Minus,Plus,Maximize,Search,ArrowUpRight,ChevronDown,ChevronUp} from 'lucide-react';
import {api} from './api';
import {getDocument,PDFDataRangeTransport,PDFWorker,AnnotationEditorType,AnnotationMode} from 'pdfjs-dist/legacy/build/pdf.mjs';
import {EventBus,PDFViewer,PDFLinkService,PDFFindController} from 'pdfjs-dist/legacy/web/pdf_viewer.mjs';
import Worker from 'pdfjs-dist/legacy/build/pdf.worker.mjs?worker&inline';
import 'pdfjs-dist/web/pdf_viewer.css';
import './pdf.css';
const bytes=base64=>Uint8Array.from(atob(base64),c=>c.charCodeAt(0));
class LocalBinaryDataFactory {async fetch({kind,filename}){return bytes(await api('pdfResource',{kind,filename}))}}
export default function PDFReader({path,title}){
 const container=useRef(),host=useRef(),controls=useRef(),[count,setCount]=useState(0),[page,setPage]=useState(1),[pageInput,setPageInput]=useState('1'),[scale,setScale]=useState(100),[loading,setLoading]=useState(true),[error,setError]=useState(''),[query,setQuery]=useState(''),[matches,setMatches]=useState(''),[password,setPassword]=useState(null),passwordReply=useRef(),[toolsOpen,setToolsOpen]=useState(true),[searchOpen,setSearchOpen]=useState(false),searchInput=useRef(),toolbarState=useRef({open:true,search:false,changed:0});toolbarState.current.open=toolsOpen;toolbarState.current.search=searchOpen;
 const showTools=value=>{toolbarState.current.changed=performance.now();setToolsOpen(value)};
 useEffect(()=>{if(searchOpen)searchInput.current?.focus()},[searchOpen]);
 useEffect(()=>{
  let closed=false,task,transport,worker,port,viewer,resize,findTimer;const el=container.current,bus=new EventBus(),lifecycle=new AbortController();setLoading(true);setError('');setCount(0);setPage(1);setPageInput('1');setQuery('');setMatches('');setPassword(null);setToolsOpen(true);setSearchOpen(false);
  const fail=e=>{if(!closed){setError(e.message||String(e));setLoading(false)}};
  const service=new PDFLinkService({eventBus:bus});
  // PDF links are opened deliberately by the native bridge. No document scripts run.
  service.addLinkAttributes=(link,url)=>{link.href=url;link.rel='noopener noreferrer';link.onclick=e=>{e.preventDefault();if(/^(https?:|mailto:)/i.test(url))api('openExternal',{url}).catch(fail)}};
  const find=new PDFFindController({linkService:service,eventBus:bus});
  const search=(value,previous=false,again=false)=>bus.dispatch('find',{source:el,type:again?'again':'',query:value,caseSensitive:false,entireWord:false,highlightAll:true,findPrevious:previous,matchDiacritics:false});
  viewer=new PDFViewer({container:el,viewer:host.current,eventBus:bus,linkService:service,findController:find,abortSignal:lifecycle.signal,annotationEditorMode:AnnotationEditorType.DISABLE,annotationMode:AnnotationMode.ENABLE,maxCanvasPixels:8*1024*1024,maxCanvasDim:4096});service.setViewer(viewer);
  controls.current={go:n=>{toolbarState.current.changed=performance.now();viewer.currentPageNumber=Math.max(1,Math.min(viewer.pagesCount,Number(n)||1));setPageInput(String(viewer.currentPageNumber))},zoom:factor=>{toolbarState.current.changed=performance.now();viewer.updateScale({scaleFactor:Math.max(.25,Math.min(4,viewer.currentScale*factor))/viewer.currentScale,drawingDelay:100})},fit:()=>{toolbarState.current.changed=performance.now();viewer.currentScaleValue='page-width'},search:(value,previous,again)=>{clearTimeout(findTimer);if(again)search(value,previous,true);else findTimer=setTimeout(()=>search(value),180)}};
  bus.on('pagesinit',()=>{if(closed)return;viewer.currentScaleValue='page-width';setCount(viewer.pagesCount)});
  bus.on('pagerendered',e=>{if(!closed){setLoading(false);if(e.error)fail(e.error)}});
  bus.on('pagechanging',e=>{if(!closed){setPage(e.pageNumber);setPageInput(String(e.pageNumber))}});
  bus.on('scalechanging',e=>{if(!closed)setScale(Math.round(e.scale*100))});
  bus.on('updatefindmatchescount',e=>{if(!closed)setMatches(`${e.matchesCount.current} of ${e.matchesCount.total}`)});
  bus.on('updatefindcontrolstate',e=>{if(!closed&&e.state===1)setMatches('No matches')});
  resize=new ResizeObserver(()=>{if(viewer.pdfDocument){if(viewer.currentScaleValue==='page-width')viewer.currentScaleValue='page-width';viewer.update()}});resize.observe(el);
  let lastScroll=0,distance=0;const readingScroll=()=>{const top=el.scrollTop,delta=top-lastScroll;lastScroll=top;const state=toolbarState.current;if(!state.open||state.search||performance.now()-state.changed<350){distance=0;return}if(delta>0)distance+=delta;if(distance>70){showTools(false);distance=0}};el.addEventListener('scroll',readingScroll,{passive:true});
  // Trackpad or touch pinch affects the document, leaving the app shell fixed.
  const wheel=e=>{if(e.ctrlKey){e.preventDefault();controls.current.zoom(Math.exp(-e.deltaY*.006))}};el.addEventListener('wheel',wheel,{passive:false});
  let pinch;const touchStart=e=>{if(e.touches.length===2){pinch={distance:Math.hypot(e.touches[0].clientX-e.touches[1].clientX,e.touches[0].clientY-e.touches[1].clientY),scale:viewer.currentScale};e.preventDefault()}};
  const touchMove=e=>{if(pinch&&e.touches.length===2){e.preventDefault();const distance=Math.hypot(e.touches[0].clientX-e.touches[1].clientX,e.touches[0].clientY-e.touches[1].clientY);viewer.updateScale({scaleFactor:Math.max(.25,Math.min(4,pinch.scale*distance/pinch.distance))/viewer.currentScale,drawingDelay:100})}};const touchEnd=()=>{pinch=null};el.addEventListener('touchstart',touchStart,{passive:false});el.addEventListener('touchmove',touchMove,{passive:false});el.addEventListener('touchend',touchEnd);
  (async()=>{
   const initial=await api('pdfRange',{path,offset:0,length:65536});if(closed)return;
   class LocalRange extends PDFDataRangeTransport {
    stopped=false;
    requestDataRange(begin,end){(async()=>{for(let offset=begin;offset<end&&!this.stopped;){const length=Math.min(1024*1024,end-offset),chunk=await api('pdfRange',{path,offset,length,version:initial.version});if(this.stopped)return;const data=bytes(chunk.data);if(data.length!==Math.min(length,initial.size-offset))throw Error('The PDF ended before the requested page data.');this.onDataRange(offset,data);offset+=data.length}})().catch(e=>{fail(e);task?.destroy()})}
    abort(){this.stopped=true}
   }
   transport=new LocalRange(initial.size,bytes(initial.data),true);port=new Worker();worker=new PDFWorker({port});
   task=getDocument({range:transport,worker,disableAutoFetch:true,disableStream:true,rangeChunkSize:65536,isEvalSupported:false,useWorkerFetch:false,BinaryDataFactory:LocalBinaryDataFactory,cMapPacked:true});
   task.onPassword=(reply,reason)=>{if(!closed){passwordReply.current=reply;setPassword(reason===2?'That password did not unlock this PDF.':'Enter the password for this PDF.');setLoading(false)}};
   const pdf=await task.promise;if(closed)return;service.setDocument(pdf);viewer.setDocument(pdf);
  })().catch(fail);
  return()=>{closed=true;lifecycle.abort();clearTimeout(findTimer);controls.current=null;passwordReply.current=null;resize.disconnect();el.removeEventListener('scroll',readingScroll);el.removeEventListener('wheel',wheel);el.removeEventListener('touchstart',touchStart);el.removeEventListener('touchmove',touchMove);el.removeEventListener('touchend',touchEnd);transport?.abort();viewer.setDocument(null);service.setDocument(null);task?.destroy().catch(()=>{});worker?.destroy();port?.terminate()};
 },[path]);
 const go=n=>controls.current?.go(n);
 return <div className="pdf-reader" aria-label={title||'PDF document'} data-controls={toolsOpen?'open':'closed'}><div className="pdf-controls" inert={!toolsOpen}><div className="pdf-controls-inner"><div className="pdf-toolbar">
  <div className="pdf-navigation"><button className="icon-button" title="Previous PDF page" disabled={page<=1} onClick={()=>go(page-1)}><ChevronLeft size={17}/></button><label><input aria-label="PDF page number" inputMode="numeric" value={pageInput} onChange={e=>setPageInput(e.target.value)} onBlur={()=>go(pageInput)} onKeyDown={e=>{if(e.key==='Enter'){go(pageInput);e.currentTarget.blur()}}}/><span>of {count||'…'}</span></label><button className="icon-button" title="Next PDF page" disabled={!count||page>=count} onClick={()=>go(page+1)}><ChevronRight size={17}/></button></div>
  <div className="pdf-zoom"><button className="icon-button" title="Zoom PDF out" onClick={()=>controls.current?.zoom(1/1.2)}><Minus size={17}/></button><span>{scale}%</span><button className="icon-button" title="Zoom PDF in" onClick={()=>controls.current?.zoom(1.2)}><Plus size={17}/></button><button className="icon-button" title="Fit PDF width" onClick={()=>controls.current?.fit()}><Maximize size={17}/></button></div>
  <div className="pdf-tools"><button className="icon-button" title="Find in PDF" aria-expanded={searchOpen} onClick={()=>{setSearchOpen(v=>!v);if(searchOpen){setQuery('');setMatches('');controls.current?.search('')}}}><Search size={17}/></button><button className="icon-button pdf-external" title="Open PDF in native viewer" onClick={()=>api('openNative',{path}).catch(e=>setError(e.message))}><ArrowUpRight size={17}/></button><button className="icon-button" title="Hide PDF controls" onClick={()=>showTools(false)}><ChevronUp size={17}/></button></div>
 </div>{searchOpen&&<div className="pdf-find"><Search size={15}/><input ref={searchInput} aria-label="Find in PDF" placeholder="Find in document" value={query} onChange={e=>{setQuery(e.target.value);setMatches('');controls.current?.search(e.target.value)}} onKeyDown={e=>{if(e.key==='Enter')controls.current?.search(query,e.shiftKey,true)}}/><span aria-live="polite">{query?matches:''}</span>{query&&<><button className="icon-button" title="Previous PDF match" onClick={()=>controls.current?.search(query,true,true)}><ChevronLeft size={15}/></button><button className="icon-button" title="Next PDF match" onClick={()=>controls.current?.search(query,false,true)}><ChevronRight size={15}/></button></>}</div>}</div></div>
 <div className="pdf-stage">{!toolsOpen&&<button className="pdf-show-controls" title="Show PDF controls" aria-label="Show PDF controls" onClick={()=>showTools(true)}><span>{page} / {count}</span><ChevronDown size={15}/></button>}<div ref={container} className="pdf-scroll" tabIndex={0}><div ref={host} className="pdfViewer"/></div>{loading&&<div className="pdf-loading" role="status">Opening PDF…</div>}{error&&<div className="pdf-message" role="alert"><p>{error}</p><button onClick={()=>api('openNative',{path})}>Open in native viewer</button></div>}{password&&<form className="pdf-message" onSubmit={e=>{e.preventDefault();passwordReply.current?.(new FormData(e.currentTarget).get('password'));setPassword(null);setLoading(true)}}><p>{password}</p><input name="password" type="password" aria-label="PDF password" autoFocus/><button type="submit">Unlock PDF</button></form>}</div></div>;
}
