import React,{useEffect,useRef,useState} from 'react';
import {quadtree} from 'd3-quadtree';
import {Plus,Minus,Scan,ArrowUpRight,Network,Search} from 'lucide-react';
import {api} from './api';
import {worldPoint,zoomAt,fitGraph} from './graphGeometry';
import {createGraphRenderer} from './graphRenderer';
import {viewportEdges} from './graphGeometry';
import {graphMetrics,placeGraphLabels} from './graphLabels';
import GraphWorker from './graph.worker.js?worker&inline';
let cachedGraph=null,cacheTimer;
window.addEventListener('vault-event',event=>{if(event.detail?.name==='files')cachedGraph=null});
export default function Graph({path='',onOpen}){
 const ref=useRef(),gpuRef=useRef(),controls=useRef({}),openRef=useRef(onOpen),[count,setCount]=useState(0),[edgeCount,setEdgeCount]=useState(0),[error,setError]=useState(''),[loading,setLoading]=useState('Loading documents…'),[selection,setSelection]=useState(null),[scale,setScale]=useState(100),[hasOverview,setHasOverview]=useState(false),[query,setQuery]=useState(''),[results,setResults]=useState([]);openRef.current=onOpen;
 useEffect(()=>{
  const worker=new GraphWorker();let observer,themeObserver,renderer,cancelled=false,cleanup=()=>{},frame=0;setSelection(null);setError('');setQuery('');setResults([]);setLoading('Loading documents…');
  async function load(){for(const kind of ['nodes','links']){let after=0,more=true,total=0;while(more&&!cancelled){const page=await api('graphPage',{kind,after});if(cancelled)return;worker.postMessage({kind,items:page.items});total+=page.items.length;after=page.cursor;more=page.more;setLoading(kind==='nodes'?`Loading ${total.toLocaleString()} documents…`:`Connecting documents · ${total.toLocaleString()} links checked`);if(kind==='nodes')setCount(total)}}if(!cancelled){setLoading('Arranging your library…');worker.postMessage({kind:'finish',path})}}
  worker.onerror=e=>{if(!cancelled){setError(e.message||'Could not prepare graph');setLoading('')}};
  const setup=async({data})=>{
   if(cancelled)return;if(data.error){setError(data.error);setLoading('');return}worker.terminate();cachedGraph={path,data};clearTimeout(cacheTimer);cacheTimer=setTimeout(()=>{cachedGraph=null},60000);
   const {nodes,edges,levels,overview}=data,canvas=ref.current,gpu=gpuRef.current,ctx=canvas.getContext('2d');setCount(nodes.length);setEdgeCount(edges.length/2);setHasOverview(!!overview);
   const overviewTree=overview?quadtree(overview.nodes,n=>n.x,n=>n.y):null;
   const tree=quadtree().x(n=>n.x).y(n=>n.y),adjacency=Array.from({length:nodes.length},()=>[]);
   for(let i=0;i<edges.length;i+=2){adjacency[edges[i]].push(edges[i+1]);adjacency[edges[i+1]].push(edges[i])}
   // Yield while building the pointer/label index. The document set is never cut.
   for(let start=0;start<nodes.length;start+=4096){if(cancelled)return;for(let i=start;i<Math.min(start+4096,nodes.length);i++)tree.add(nodes[i]);await new Promise(resolve=>{const c=new MessageChannel();c.port1.onmessage=()=>{c.port1.close();c.port2.close();resolve()};c.port2.postMessage(0)})}
   if(cancelled)return;
   try{renderer=createGraphRenderer(gpu,nodes,edges,levels,overview)}catch(e){setError('Using the compatible graph renderer.')}
   let width=900,height=600,transform={x:450,y:300,k:1},selected=null,hovered=null,initialized=false,gesture=null;
   const pointers=new Map();
   let palette={};const colors=()=>{const style=getComputedStyle(document.documentElement);palette=Object.fromEntries(['accent','text','muted','bg'].map(k=>[k,style.getPropertyValue('--'+k).trim()]))};colors();
   function visible(t,callback){const a=worldPoint({x:-120,y:-30},t),b=worldPoint({x:width+120,y:height+30},t);tree.visit((node,x0,y0,x1,y1)=>{if(x1<a.x||y1<a.y||x0>b.x||y0>b.y)return true;if(!node.length){do{const n=node.data;if(n.x>=a.x&&n.x<=b.x&&n.y>=a.y&&n.y<=b.y)callback(n)}while(node=node.next)}return false})}
   const draw=()=>{
    const ratio=Math.min(2,devicePixelRatio||1);ctx.setTransform(ratio,0,0,ratio,0,0);ctx.clearRect(0,0,width,height);const metrics=graphMetrics(transform.k),visibleNodes=[];if(transform.k>.2||nodes.length<60||!renderer)visible(transform,n=>visibleNodes.push(n));const visibleEdges=renderer&&transform.k>.2?viewportEdges(adjacency,visibleNodes.map(n=>n.index)):null;renderer?.draw(transform,width,height,ratio,palette,visibleEdges);
    const screen=n=>({x:n.x*transform.k+transform.x,y:n.y*transform.k+transform.y});
    if(!renderer){
     // Compatibility mode shows density at a distance, individual nodes on zoom.
     const cells=new Map();visible(transform,n=>{const p=screen(n),key=Math.floor(p.x/4)+':'+Math.floor(p.y/4);if(!cells.has(key))cells.set(key,p)});ctx.fillStyle=palette.accent;for(const p of cells.values()){ctx.beginPath();ctx.arc(p.x,p.y,2,0,Math.PI*2);ctx.fill()}
     if(transform.k>.3){ctx.strokeStyle=palette.muted;ctx.globalAlpha=.15;ctx.beginPath();visible(transform,n=>{const p=screen(n);for(const id of adjacency[n.index]){const target=screen(nodes[id]);ctx.moveTo(p.x,p.y);ctx.lineTo(target.x,target.y)}});ctx.stroke();ctx.globalAlpha=1}
    }
    if(selected){const p=screen(selected);ctx.strokeStyle=palette.accent;ctx.globalAlpha=.65;ctx.beginPath();for(const id of adjacency[selected.index]){const n=screen(nodes[id]);ctx.moveTo(p.x,p.y);ctx.lineTo(n.x,n.y)}ctx.stroke();ctx.globalAlpha=1;ctx.fillStyle=palette.text;ctx.beginPath();ctx.arc(p.x,p.y,6,0,Math.PI*2);ctx.fill()}
    // Readable screen-space text expands more slowly than world-space spacing.
    const fontSize=metrics.fontSize;ctx.font=`${fontSize}px system-ui`;ctx.textBaseline='middle';
    const candidates=visibleNodes.map(n=>({...screen(n),index:n.index,radius:n===selected?6:metrics.nodeDiameter/2,degree:adjacency[n.index].length,label:n.title,priority:n===selected?3:n===hovered?2:0}));
    if(hovered?.isGroup)candidates.push({...screen(hovered),index:'group',radius:3,label:`${hovered.count.toLocaleString()} documents`,priority:2});
    const labels=placeGraphLabels(candidates,{width,height,fontSize,measure:text=>ctx.measureText(text).width,top:width<700?145:80,maxTextWidth:Math.min(300,width*.42)});
    for(const label of labels){ctx.globalAlpha=label.priority?1:metrics.labelOpacity;if(!ctx.globalAlpha)continue;ctx.fillStyle=palette.bg;ctx.beginPath();ctx.roundRect(label.x,label.y,label.w,label.h,6);ctx.fill();ctx.fillStyle=label.priority?palette.text:palette.muted;ctx.fillText(label.text,label.x+6,label.y+label.h/2)}ctx.globalAlpha=1;

   };
   const render=()=>{if(!frame)frame=setTimeout(()=>{frame=0;if(!cancelled)draw()},16)};
   const change=t=>{transform=t;setScale(t.k*100);render()};
   const fit=()=>change(fitGraph(nodes,width,height));
   function select(n,focus=false){if(n?.isGroup){selected=null;setSelection(null);change({k:.5,x:width/2-n.x*.5,y:height/2-n.y*.5});return}selected=n;setSelection(n?{path:n.path,title:n.title}:null);if(focus&&n)change({k:1.8,x:width/2-n.x*1.8,y:height/2-n.y*1.8});else render()}
   controls.current={fit,zoom:factor=>change(zoomAt(transform,{x:width/2,y:height/2},factor)),search:text=>{const clean=text.trim().toLocaleLowerCase();const matches=[];if(clean)for(const n of nodes){if(n.title.toLocaleLowerCase().includes(clean)||n.path.toLocaleLowerCase().includes(clean))matches.push(n);if(matches.length===8)break}setResults(matches)},focus:n=>{select(n,true);setResults([]);setQuery('')}};
   observer=new ResizeObserver(entries=>{const r=entries[0].contentRect,old={width,height};width=r.width;height=r.height;const ratio=Math.min(2,devicePixelRatio||1);for(const c of [canvas,gpu]){c.width=Math.round(width*ratio);c.height=Math.round(height*ratio)}if(!initialized&&width&&height){const core=overview?.nodes.filter(n=>n.linked);change(fitGraph(core?.length?core:nodes,width,height));initialized=true}else change({...transform,x:transform.x+(width-old.width)/2,y:transform.y+(height-old.height)/2})});observer.observe(canvas);
   themeObserver=new MutationObserver(()=>{colors();render()});themeObserver.observe(document.documentElement,{attributes:true,attributeFilter:['style','data-mode']});
   const point=e=>{const r=canvas.getBoundingClientRect();return{x:e.clientX-r.left,y:e.clientY-r.top}};
   const hit=p=>{const w=worldPoint(p,transform);return (overviewTree&&transform.k<.09?overviewTree:tree).find(w.x,w.y,Math.max(8,9/transform.k))};
   const pinch=()=>{const[a,b]=[...pointers.values()];return{middle:{x:(a.x+b.x)/2,y:(a.y+b.y)/2},distance:Math.max(1,Math.hypot(a.x-b.x,a.y-b.y))}};
   const down=e=>{if(e.button!==0)return;e.preventDefault();const p=point(e);pointers.set(e.pointerId,p);canvas.setPointerCapture(e.pointerId);if(pointers.size===2){gesture={...pinch(),transform:{...transform},pinch:true};return}const node=hit(p);gesture={start:p,last:p,node,moved:false};canvas.style.cursor=node?'grabbing':'move'};
   const move=e=>{const p=point(e);if(!pointers.has(e.pointerId)){const n=hit(p);canvas.style.cursor=n?'pointer':'grab';if(n!==hovered){hovered=n;render()}return}pointers.set(e.pointerId,p);if(pointers.size===2&&gesture?.pinch){const next=pinch(),z=zoomAt(gesture.transform,gesture.middle,next.distance/gesture.distance);change({...z,x:z.x+next.middle.x-gesture.middle.x,y:z.y+next.middle.y-gesture.middle.y});return}if(!gesture||gesture.pinch)return;if(Math.hypot(p.x-gesture.start.x,p.y-gesture.start.y)>5)gesture.moved=true;if(gesture.moved){if(gesture.node&&!gesture.node.isGroup&&transform.k>.35){const w=worldPoint(p,transform),n=gesture.node;tree.remove(n);n.x=w.x;n.y=w.y;tree.add(n);renderer?.move(n);render()}else change({...transform,x:transform.x+p.x-gesture.last.x,y:transform.y+p.y-gesture.last.y})}gesture.last=p};
   const up=e=>{pointers.delete(e.pointerId);if(gesture?.node&&!gesture.moved&&e.type!=='pointercancel')select(gesture.node);gesture=null;canvas.style.cursor='grab';if(pointers.size===1){const p=[...pointers.values()][0];gesture={start:p,last:p,moved:true}}};
   const wheel=e=>{e.preventDefault();change(zoomAt(transform,point(e),Math.exp(-e.deltaY*.002)))};
   const dbl=e=>{const n=hit(point(e));if(n?.isGroup)select(n);else if(n&&transform.k>.35)openRef.current(n.path);else change(zoomAt(transform,point(e),2))};
   const key=e=>{if(['+','=','-','0','ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)){e.preventDefault();if(e.key==='0')fit();else if(['+','=','-'].includes(e.key))controls.current.zoom(e.key==='-'?.8:1.25);else change({...transform,x:transform.x+(e.key==='ArrowLeft'?60:e.key==='ArrowRight'?-60:0),y:transform.y+(e.key==='ArrowUp'?60:e.key==='ArrowDown'?-60:0)})}if(e.key==='Enter'&&selected)openRef.current(selected.path)};
   const lost=e=>{e.preventDefault();setError('Graphics paused. Reopen the graph to restore it.');renderer=null;render()};gpu.addEventListener('webglcontextlost',lost);
   const events={pointerdown:down,pointermove:move,pointerup:up,pointercancel:up,wheel,dblclick:dbl,keydown:key};Object.entries(events).forEach(([name,fn])=>canvas.addEventListener(name,fn,{passive:false}));cleanup=()=>{Object.entries(events).forEach(([name,fn])=>canvas.removeEventListener(name,fn));gpu.removeEventListener('webglcontextlost',lost)};
   setLoading('');render();
  };
  worker.onmessage=event=>{setup(event).catch(e=>{if(!cancelled){setError(e.message);setLoading('')}})};
  if(cachedGraph?.path===path)worker.onmessage({data:cachedGraph.data});else load().catch(e=>{if(!cancelled){setError(e.message);setLoading('')}});
  return()=>{cancelled=true;worker.terminate();clearTimeout(frame);cleanup();renderer?.destroy();observer?.disconnect();themeObserver?.disconnect();controls.current={}};
 },[path]);
 useEffect(()=>{const timer=setTimeout(()=>controls.current.search?.(query),150);return()=>clearTimeout(timer)},[query]);
 return <div className="graph-view"><canvas className="graph-gpu" ref={gpuRef} aria-hidden="true"/><canvas className="graph-interaction" ref={ref} tabIndex={0} aria-label="Document graph. Drag to pan, pinch or scroll to zoom. Zoom in to drag a node. Arrow keys pan; plus and minus zoom; zero fits all."/><div className="graph-heading"><Network size={18}/><div><strong>{path?'Document connections':hasOverview&&scale<9?'Your library, connected':'Your connected library'}</strong><small>{loading||`${count.toLocaleString()} documents · ${edgeCount.toLocaleString()} connections`}</small></div></div><div className="graph-search"><label><Search size={15}/><input aria-label="Find a document in the graph" placeholder="Find in graph" value={query} onChange={e=>setQuery(e.target.value)} disabled={!!loading}/></label>{results.length>0&&<div className="graph-search-results">{results.map(n=><button key={n.path} onClick={()=>controls.current.focus?.(n)}><strong>{n.title}</strong><small>{n.path}</small></button>)}</div>}</div>{error&&<p className="graph-error">{error}</p>}<div className="graph-controls"><button title="Zoom out" disabled={!!loading} onClick={()=>controls.current.zoom?.(.8)}><Minus size={18}/></button><span>{scale<10?scale.toFixed(1):Math.round(scale)}%</span><button title="Zoom in" disabled={!!loading} onClick={()=>controls.current.zoom?.(1.25)}><Plus size={18}/></button><i/><button title="Fit all documents" disabled={!!loading} onClick={()=>controls.current.fit?.()}><Scan size={18}/></button></div>{selection?<button className="graph-selection" onClick={()=>onOpen(selection.path)}><span>{selection.title}</span><ArrowUpRight size={17}/></button>:<div className="graph-hint">{hasOverview&&scale<9?'Groups expand into documents as you zoom · Select a group to explore':'Drag to explore · Pinch to zoom · Select a document to open'}</div>}</div>
}
