import React,{useEffect,useRef,useState} from 'react';
import {ArrowLeft,ArrowUp,Check,ChevronDown,Copy,FileText,Plus,Square,X} from 'lucide-react';
import {render} from './markdown';
import {api} from './api';
import {useModels} from './useModels';
import {assistantName,assistantText} from './assistantMessages';
import './labAssistant.css';

export default function LabAssistant({provider,onProvider,remote,onTarget,deviceLabel,model,onModel,file,includeFile,onIncludeFile,prompt,onPrompt,history,busy,edits,onEdits,onSend,onStop,onClose,onClear,onConnect}) {
 const {models}=useModels();
 const [copied,setCopied]=useState(''),[settings,setSettings]=useState(false);
 const input=useRef(),scroll=useRef(),follow=useRef(true);
 const localModels=models.filter(m=>(m.provider==='remote')===remote);
 const unsupported=provider!=='local' && !remote && deviceLabel!=='This Mac';
 const last=history.at(-1);
 useEffect(()=>{if(input.current){input.current.style.height='auto';input.current.style.height=Math.min(input.current.scrollHeight,120)+'px';}},[prompt]);
 useEffect(()=>{if(follow.current && scroll.current)scroll.current.scrollTop=scroll.current.scrollHeight;},[history,last?.status]);
 useEffect(()=>{follow.current=true;},[provider,remote]);
 async function copy(entry){await api('copy',{text:assistantText(entry.result)});setCopied(entry.id);setTimeout(()=>setCopied(''),1500);}
 function suggestion(text){onPrompt(text);onIncludeFile(Boolean(file?.content));input.current?.focus();}
 return <aside className="lab-assistant-pane" aria-label="Lab assistant">
  <header className="lab-assistant-header">
   <button className="lab-assistant-back" aria-label="Back to notebook" onClick={onClose}><ArrowLeft size={18}/></button>
   <strong>Assistant</strong>
   <button className="lab-assistant-settings" aria-label="Assistant settings" aria-expanded={settings} onClick={()=>setSettings(!settings)}>{assistantName(provider)}<ChevronDown size={13}/></button>
   <div><button aria-label="New assistant conversation" title="New conversation" disabled={busy||!history.length} onClick={onClear}><Plus size={18}/></button><button className="lab-assistant-close" aria-label="Close assistant" onClick={onClose}><X size={18}/></button></div>
  </header>
  {settings&&<><div className="lab-assistant-pickers">
   <select aria-label="Assistant provider" value={provider} disabled={busy} onChange={e=>onProvider(e.target.value)}><option value="local">Local model</option><option value="codex">Codex</option><option value="claude">Claude Code</option></select>
   <select aria-label="Assistant runs on" value={remote?'remote':'local'} disabled={busy} onChange={e=>onTarget(e.target.value)}><option value="local">{deviceLabel}</option>{deviceLabel!=='This Mac'&&<option value="remote">Paired Mac</option>}</select>
  </div>
  {provider==='local'&&<div className="lab-assistant-model"><select aria-label="Assistant model" disabled={busy} value={model} onChange={e=>onModel(e.target.value)}><option value="">{remote?'Mac’s selected model':'Vault’s selected model'}</option>{localModels.map(m=><option key={m.id} value={m.id.replace(/^remote\//,'')}>{m.name}</option>)}</select><span>Offline</span></div>}</>}
  <div className="lab-assistant-transcript" ref={scroll} onScroll={()=>{const el=scroll.current;follow.current=el.scrollHeight-el.clientHeight-el.scrollTop<80;}}>
   {unsupported?<div className="lab-assistant-setup"><h3>Connect your Mac.</h3><p>Use {assistantName(provider)} with your Mac’s login while your notebook keeps running here.</p><button onClick={onConnect}>Connect Mac <ArrowUp size={14} style={{transform:'rotate(45deg)'}}/></button></div>:!history.length?<div className="lab-assistant-empty"><div className="lab-assistant-orbit" aria-hidden="true">✳</div><h3>Work through it together.</h3><p>Ask a question, explore an idea,<br/>or get help with your code.</p><div>{['Explain this file','Help me find a problem','Suggest a small test'].map(text=><button key={text} onClick={()=>suggestion(text)}>{text} <ArrowUp size={13} style={{transform:'rotate(45deg)'}}/></button>)}</div></div>:null}
   {history.map(entry=><section className="lab-assistant-turn" key={entry.id}>
    <div className="lab-assistant-question">{entry.attachment&&<small><FileText size={12}/>{entry.attachment}</small>}<p>{entry.prompt}</p></div>
    {entry.status==='pending'?<div className="lab-assistant-working" role="status"><span/>{assistantName(provider)} is working…</div>:entry.error?<div className="lab-assistant-error" role="alert">{entry.error}</div>:<div className="lab-assistant-response"><div className="lab-markdown" dangerouslySetInnerHTML={{__html:render(assistantText(entry.result),{chat:true})}}/>{entry.result?.status!=='ok'&&<p className="lab-assistant-error">{entry.result?.outputs?.find(o=>o.output_type==='error')?.evalue || 'The assistant could not finish this request.'}</p>}{assistantText(entry.result)&&<button className="lab-assistant-copy" aria-label="Copy assistant reply" onClick={()=>copy(entry).catch(()=>{})}>{copied===entry.id?<Check size={13}/>:<Copy size={13}/>}</button>}</div>}
   </section>)}
  </div>
  <form className="lab-assistant-composer" onSubmit={e=>{follow.current=true;onSend(e);}}>
   <div className="lab-assistant-context-row">{file?.content&&<button type="button" className={'lab-assistant-context '+(includeFile?'selected':'')} aria-pressed={includeFile} disabled={busy} onClick={()=>onIncludeFile(!includeFile)}><FileText size={13}/><span>{includeFile?file.path.split('/').pop():'Add current file'}</span>{includeFile?<X size={12}/>:<Plus size={12}/>}</button>}{provider!=='local'&&<select aria-label="Assistant file access" value={edits?'edit':'read'} disabled={busy} onChange={e=>onEdits(e.target.value==='edit')}><option value="read">Read only</option><option value="edit">Can edit files</option></select>}</div>
   <textarea ref={input} aria-label="Assistant prompt" value={prompt} onFocus={()=>setSettings(false)} onChange={e=>onPrompt(e.target.value)} placeholder="Ask about your work…" rows={1} maxLength={4000} disabled={busy||unsupported} onKeyDown={e=>{if(e.key==='Enter'&&(e.metaKey||e.ctrlKey)){e.preventDefault();if(!busy&&prompt.trim()&&!unsupported){follow.current=true;onSend(e);}}}}/>
   <div className="lab-assistant-compose-foot"><small>{provider==='local'?remote?'Model runs on your Mac':'Model runs on this device':'Uses your Mac login · Online'}</small>{busy?<button type="button" className="lab-assistant-send" aria-label="Stop assistant" onClick={onStop}><Square size={14} fill="currentColor"/></button>:<button className="lab-assistant-send" aria-label="Send to assistant" disabled={!prompt.trim()||unsupported}><ArrowUp size={18}/></button>}</div>
  </form>
 </aside>;
}
