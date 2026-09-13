import {useState,useEffect} from 'react';
import {api} from './api';import {chooseModel} from './modelSelection';
export function useModels(){
 const [catalog,setCatalog]=useState({models:[],issues:[]}),[selected,setSelected]=useState(''),[checking,setChecking]=useState(false);
 async function refresh(){setChecking(true);try{const value=await api('models');setCatalog(current=>({...value,models:[...value.models,...current.models.filter(m=>m.provider==='remote')]}));setSelected(current=>chooseModel(value.models,[current,value.selected],value.remoteOption))}finally{setChecking(false)}}
 useEffect(()=>{refresh().catch(()=>{});const listener=()=>refresh().catch(()=>{});window.addEventListener('models-changed',listener);window.addEventListener('focus',listener);return()=>{window.removeEventListener('models-changed',listener);window.removeEventListener('focus',listener)}},[]);
 useEffect(()=>{if(!catalog.remoteOption)return;let cancelled=false;api('modelStatus').then(r=>{if(cancelled)return;setCatalog(c=>({...c,models:[...c.models.filter(m=>m.provider!=='remote'),...(r.models||[]).map(m=>({...m,id:'remote/'+m.id,provider:'remote',offline:false}))]}))}).catch(()=>{});return()=>{cancelled=true}},[catalog.remoteOption]);
 const models=catalog.models.length?catalog.models:catalog.remoteOption?[{id:'paired-mac',name:'Paired Mac',provider:'remote',precision:'',context:16384}]:[];
 const current=models.find(m=>m.id===selected)||{id:selected,name:selected?'Model unavailable':'Choose a model',provider:'local'};
 function select(id){setSelected(id);api('selectModel',{id}).catch(()=>{});window.dispatchEvent(new CustomEvent('model-selected',{detail:id}))}
 useEffect(()=>{const event=e=>setSelected(e.detail);window.addEventListener('model-selected',event);return()=>window.removeEventListener('model-selected',event)},[]);
 return{catalog,models,current,selected,select,refresh,checking};
}
export const modelSize=bytes=>bytes?bytes>=1e9?(bytes/1e9).toFixed(1)+' GB':Math.round(bytes/1e6)+' MB':'';
