import React,{useEffect,useRef} from 'react';
import {EditorView,keymap,placeholder} from '@codemirror/view';
import {EditorState} from '@codemirror/state';
import {markdown} from '@codemirror/lang-markdown';
import {defaultKeymap,history,historyKeymap,indentWithTab} from '@codemirror/commands';
import {searchKeymap,highlightSelectionMatches} from '@codemirror/search';
import {syntaxHighlighting,defaultHighlightStyle,foldGutter} from '@codemirror/language';
import {autocompletion} from '@codemirror/autocomplete';
import {api} from './api';
export default function Editor({value,path,onChange,onSave,readOnly=false}){
 const host=useRef(),view=useRef(),change=useRef(onChange),save=useRef(onSave);change.current=onChange;save.current=onSave;
 useEffect(()=>{
  async function links(context){const word=context.matchBefore(/\[\[[^\]\n]*/);if(!word)return null;const q=word.text.slice(2);if(q.length<2)return null;try{const rows=await api('search',{query:'file:'+q});return {from:word.from+2,options:rows.slice(0,30).map(r=>({label:r.title,detail:r.path,apply:r.path.replace(/\.md$/,'')+']]',type:'text'}))}}catch{return null}}
  view.current=new EditorView({parent:host.current,state:EditorState.create({doc:value,extensions:[history(),markdown(),syntaxHighlighting(defaultHighlightStyle),highlightSelectionMatches(),foldGutter(),autocompletion({override:[links]}),keymap.of([{key:'Mod-s',run:()=>{save.current();return true}},...defaultKeymap,...historyKeymap,...searchKeymap,indentWithTab]),EditorView.lineWrapping,placeholder('Start writing…'),EditorState.readOnly.of(readOnly),EditorView.updateListener.of(v=>{if(v.docChanged)change.current(v.state.doc.toString())}),EditorView.theme({'&':{height:'100%',fontSize:'var(--document-size)' ,backgroundColor:'var(--bg)',color:'var(--text)'},'.cm-content':{fontFamily:'ui-monospace, SFMono-Regular, Menlo, monospace',padding:'28px 36px',minHeight:'100%'},'.cm-scroller':{overflow:'auto',lineHeight:'1.8'},'.cm-gutters':{backgroundColor:'var(--bg)',border:'none',color:'var(--faint)'},'.cm-activeLine':{backgroundColor:'transparent'},'.cm-cursor':{borderLeftColor:'var(--text)'},'.cm-selectionBackground, &.cm-focused .cm-selectionBackground':{backgroundColor:'var(--accent-soft)'},'.cm-tooltip':{backgroundColor:'var(--elevated)',border:'1px solid var(--border)'},'.cm-search':{padding:'8px'}},{dark:true})]})});
  return ()=>{view.current?.destroy();view.current=null};
 },[path,readOnly]);
 useEffect(()=>{const v=view.current;if(v&&value!==v.state.doc.toString())v.dispatch({changes:{from:0,to:v.state.doc.length,insert:value}})},[value]);
 return <div className="editor" ref={host}/>;
}
