import React,{useEffect,useState} from 'react';
import {Download,Check,Pause,ArrowDownToLine} from 'lucide-react';
import {api} from './api';
import {modelSize} from './useModels';

export default function StarterModels({onError,onInstalled}) {
 const [models,setModels]=useState([]),[download,setDownload]=useState({}),[starting,setStarting]=useState(false);
 async function refresh(){const value=await api('starterModels');setModels(value.models);setDownload(value.download||{})}
 useEffect(()=>{refresh().catch(onError);const event=e=>{if(e.detail.name!=='modelDownload')return;const state=e.detail.data;setDownload(state);if(state.status==='ready'){refresh().catch(onError);onInstalled();window.dispatchEvent(new Event('models-changed'))}};window.addEventListener('vault-event',event);return()=>window.removeEventListener('vault-event',event)},[]);
 async function start(id){setStarting(true);try{const value=await api('downloadStarterModel',{id});setDownload(value.download)}catch(e){onError(e)}finally{setStarting(false)}}
 const active=download.status==='downloading';
 return <section className="starter-model-section">
  <div className="settings-section-title"><h2>A little intelligence. Entirely yours.</h2><p>Two Qwen companions, ready to install. No account, API key, or separate runtime.</p></div>
  <div className="starter-model-grid">{models.map((m,i)=>{const current=download.id===m.id,percent=current?Math.min(100,Math.round(100*(download.received||0)/(download.total||m.bytes))):0;return <article className="settings-card starter-model-card" key={m.id}>
   <div className="starter-model-heading"><span className="starter-glyph" aria-hidden="true">{i===0?'✦':'✧'}</span><span className="model-starter-label">{i===0?'EVERYDAY':'MORE CAPABLE'}</span></div>
   <h3>{m.name}</h3><p>{i===0?'A smaller companion for quick questions, summaries, and taking your ideas further.':'More room for reasoning through a document and exploring a difficult question.'}</p>
   <div className="model-tags"><span>{modelSize(m.bytes)} download</span><span>{m.precision}</span><span>{m.license}</span></div>
   <small>{i===0?'Start here on iPhone or iPad.':'Needs more available memory.'} Both run locally after setup.</small>
   {m.installed?<div className="starter-ready"><Check size={17}/> Installed · ready offline</div>:<button className="primary" disabled={starting||(active&&!current)} onClick={()=>current&&active?api('pauseStarterDownload').catch(onError):start(m.id)}>{current&&active?<Pause size={16}/>:<ArrowDownToLine size={16}/>} {current&&active?'Pause download':current&&['paused','error'].includes(download.status)?'Resume download':'Install '+(i===0?'smaller Qwen':'larger Qwen')}</button>}
   {current&&!m.installed&&<div className="starter-progress" aria-live="polite"><progress max="100" value={percent} aria-label={`${m.name} download`}/><div><span>{download.status==='paused'?'Paused · progress saved':download.status==='error'?'Download needs attention':download.file||'Preparing…'}</span><span>{percent}%</span></div>{download.message&&<p className="inline-error">{download.message}</p>}</div>}
  </article>})}</div>
  <p className="starter-download-note"><Download size={15}/><span>Download once from Hugging Face. Files are checked against pinned SHA-256 checksums. Keep Vault open while downloading on iPhone or iPad; interrupted downloads resume. Your documents and conversations are never included in these requests.</span></p>
 </section>
}
