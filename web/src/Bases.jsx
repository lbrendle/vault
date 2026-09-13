import React,{useEffect,useMemo,useState} from 'react';
import {parse} from 'yaml';
import {api} from './api';
import {parseBase,matches,property,baseFolder} from './base';
import {updateProperties,frontmatter} from './markdown';
export default function Bases({doc,onOpen,onError}){
 const [rows,setRows]=useState([]),[selected,setSelected]=useState(0),[sort,setSort]=useState(null),[refresh,setRefresh]=useState(0);
 let base,error;try{base=parseBase(doc.content)}catch(e){error=e.message}
 useEffect(()=>{if(!base)return;api('baseRows',{folder:baseFolder(base,doc.path.split('/').slice(0,-1).join('/'))}).then(data=>setRows(data.map(r=>({...r,properties:parse(r.frontmatter)||{}})))).catch(onError)},[doc.path,doc.content,refresh]);
 if(error)return <div className="empty"><p>{error}</p></div>;
 const view=base.views?.[selected]||{},cols=view.order||['file.name','status'];let filtered=[];
 try{filtered=rows.filter(r=>matches(base.filters,r)&&matches(view.filters,r));if(sort)filtered.sort((a,b)=>String(property(a,sort.key)??'').localeCompare(String(property(b,sort.key)??''),undefined,{numeric:true})*sort.dir)}catch(e){error=e.message}
 async function edit(row,key){if(key.startsWith('file.')||key.startsWith('formula.'))return;const old=property(row,key),next=window.prompt('Edit '+key,typeof old==='object'?JSON.stringify(old):String(old??''));if(next===null)return;try{const d=await api('read',{path:row.path});const props=frontmatter(d.content).properties;props[key.replace(/^note\./,'')]=parse(next);await api('save',{path:d.path,revision:d.revision,content:updateProperties(d.content,props)});setRefresh(x=>x+1)}catch(e){onError(e)}}
 return <div className="bases"><div className="base-tabs">{(base.views||[]).map((v,i)=><button className={selected===i?'selected':''} onClick={()=>setSelected(i)} key={i}>{v.name}</button>)}</div>{error?<div className="notice">{error}. Open source mode to inspect the definition; this view has not been approximated.</div>:<><div className="view-caption">{filtered.length} records · Double-click a property to edit</div><div className="table-scroll"><table><thead><tr>{cols.map(c=><th key={c} onClick={()=>setSort({key:c,dir:sort?.key===c?-sort.dir:1})}>{base.properties?.[c]?.displayName||base.properties?.['note.'+c]?.displayName||c.replace(/^(note|file)\./,'')}{sort?.key===c?(sort.dir===1?' ↑':' ↓'):''}</th>)}</tr></thead><tbody>{filtered.map(r=><tr key={r.path}>{cols.map(c=><td key={c} onDoubleClick={()=>edit(r,c)}>{c==='file.name'?<button className="text-link" onClick={()=>onOpen(r.path)}>{r.title}</button>:typeof property(r,c)==='object'&&property(r,c)!==null?JSON.stringify(property(r,c)):String(property(r,c)??'—')}</td>)}</tr>)}</tbody></table></div>{rows.length===1000&&<div className="notice">Showing the first 1,000 folder records.</div>}</>}</div>
}
