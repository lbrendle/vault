import {useEffect,useState} from 'react';
// Returns `value`, held back while it keeps changing and released `delay` ms after it settles.
// A zero delay, or a different `scope` (another document), passes the value straight through.
export function useDebounced(value,delay,scope){
 const [held,setHeld]=useState({value,scope}),immediate=delay<=0||held.scope!==scope;
 useEffect(()=>{
  const settle=()=>setHeld(current=>current.value===value&&current.scope===scope?current:{value,scope});
  if(immediate){settle();return}
  const timer=setTimeout(settle,delay);return()=>clearTimeout(timer);
 },[value,delay,scope,immediate]);
 return immediate?value:held.value;
}
