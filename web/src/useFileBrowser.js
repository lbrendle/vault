import {useEffect,useRef,useState} from 'react';
import {api} from './api';
import {FileBrowser} from './fileBrowser';
export function useFileBrowser(path,active,epoch,running,onError){
 const [view,setView]=useState({rows:[],more:false,busy:false}),error=useRef(onError),browser=useRef();error.current=onError;
 if(!browser.current)browser.current=new FileBrowser(args=>api('list',args),setView,e=>error.current(e));
 useEffect(()=>{browser.current.reset(path,active);return()=>browser.current.dispose()},[path,active,epoch]);
 useEffect(()=>{if(active&&!running)browser.current.scheduleRefresh()},[active,running]);
 useEffect(()=>{const changed=e=>{if(e.detail.name==='files')browser.current.scheduleRefresh()};window.addEventListener('vault-event',changed);return()=>window.removeEventListener('vault-event',changed)},[]);
 return {...view,refresh:()=>browser.current.refresh(),loadMore:()=>browser.current.loadMore()};
}
