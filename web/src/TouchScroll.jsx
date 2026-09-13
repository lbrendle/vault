import React,{useEffect,useRef} from 'react';
import {attachTouchScroll} from './phoneScrollGesture.js';

export default function TouchScroll({children,className='',...props}){
 const pane=useRef();
 useEffect(()=>attachTouchScroll(pane.current),[]);
 return <div ref={pane} className={'touch-scroll '+className} {...props}>{children}</div>;
}
