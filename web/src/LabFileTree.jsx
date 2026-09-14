import React,{useEffect,useMemo,useState} from 'react';
import {BookOpen,ChevronRight,FileCode2,FileText,Folder,Plus,Search,X} from 'lucide-react';

export default function LabFileTree({files,selected,busy,onOpen,onNew,onClose}) {
 const [query,setQuery]=useState(''),[expanded,setExpanded]=useState(new Set());
 const isRunRecord=file=>/^runs\/[^/]+\/record\.json$/.test(file.path);
 const source=files.filter(file=>!isRunRecord(file));
 const tree=useMemo(()=>{
  const root={folders:new Map(),files:[]};
  for(const file of source){let node=root;const parts=file.path.split('/');parts.pop();let path='';for(const name of parts){path=path?path+'/'+name:name;if(!node.folders.has(name))node.folders.set(name,{name,path,folders:new Map(),files:[]});node=node.folders.get(name)}node.files.push(file)}
  return root;
 },[files]);
 useEffect(()=>{const parts=(selected||'').split('/');parts.pop();setExpanded(previous=>{const next=new Set(previous);for(let i=1;i<=parts.length;i++)next.add(parts.slice(0,i).join('/'));return next})},[selected]);
 const icon=file=>file.ext==='ipynb'?<BookOpen size={15}/>:file.ext==='py'?<FileCode2 size={15}/>:<FileText size={15}/>;
 const row=(file,depth=0,full=false)=><button key={file.path} aria-current={selected===file.path?'page':undefined} disabled={busy} className={selected===file.path?'selected':''} style={{paddingLeft:12+depth*14}} onClick={()=>onOpen(file.path)}>{icon(file)}<span title={file.path}>{full?file.path:file.path.split('/').pop()}</span></button>;
 function branch(node,depth=0){return <>{[...node.folders.values()].sort((a,b)=>a.name.localeCompare(b.name,undefined,{numeric:true})).map(folder=><React.Fragment key={folder.path}><button className="lab-folder-row" aria-expanded={expanded.has(folder.path)} style={{paddingLeft:12+depth*14}} onClick={()=>setExpanded(previous=>{const next=new Set(previous);if(next.has(folder.path))next.delete(folder.path);else next.add(folder.path);return next})}><ChevronRight size={12}/><Folder size={15}/><span>{folder.name}</span></button>{expanded.has(folder.path)&&branch(folder,depth+1)}</React.Fragment>)}{node.files.map(file=>row(file,depth))}</>}
 const results=source.filter(file=>file.path.toLowerCase().includes(query.trim().toLowerCase()));
 const runs=files.filter(isRunRecord).slice(-25).reverse();
 return <aside className="lab-project-tree" aria-label="Project files">
  <div className="lab-tree-title"><span>Files <small>{source.length}</small></span><div><button disabled={busy} title="New file" aria-label="New file" onClick={onNew}><Plus size={16}/></button><button aria-label="Close project files" onClick={onClose}><X size={16}/></button></div></div>
  <label className="lab-file-filter"><Search size={14}/><input aria-label="Filter project files" value={query} onChange={e=>setQuery(e.target.value)} placeholder="Filter files…"/>{query&&<button aria-label="Clear file filter" onClick={()=>setQuery('')}><X size={13}/></button>}</label>
  <div className="lab-tree-files">{query?results.map(file=>row(file,0,true)):branch(tree)}{!results.length&&<p className="lab-files-empty">No matching files.</p>}</div>
  {runs.length>0&&<details className="lab-runs"><summary><ChevronRight size={13}/> Run history <small>{runs.length}</small></summary>{runs.map(file=><button key={file.path} disabled={busy} onClick={()=>onOpen(file.path)}><FileText size={13}/><span>{file.path.split('/')[1]}</span></button>)}</details>}
 </aside>;
}
