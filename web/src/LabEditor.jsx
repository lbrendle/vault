import React,{useEffect,useRef} from 'react';
import {EditorView,keymap,lineNumbers,highlightActiveLine} from '@codemirror/view';
import {EditorState,Compartment} from '@codemirror/state';
import {history,defaultKeymap,historyKeymap,indentWithTab} from '@codemirror/commands';
import {syntaxHighlighting,HighlightStyle,bracketMatching,indentOnInput,foldGutter} from '@codemirror/language';
import {autocompletion,closeBrackets,closeBracketsKeymap,completionKeymap} from '@codemirror/autocomplete';
import {tags} from '@lezer/highlight';
import {python} from '@codemirror/lang-python';
import {markdown} from '@codemirror/lang-markdown';
import {searchKeymap} from '@codemirror/search';
const colors=HighlightStyle.define([{tag:[tags.keyword,tags.operatorKeyword],color:'var(--lab-keyword)'},{tag:[tags.string,tags.special(tags.string)],color:'var(--lab-string)'},{tag:[tags.number,tags.bool],color:'var(--lab-number)'},{tag:tags.comment,color:'var(--muted)',fontStyle:'italic'},{tag:[tags.function(tags.variableName),tags.definition(tags.variableName)],color:'var(--lab-function)'}]);
export default function LabEditor({value,onChange,onRun,onSave,language='python',file=false,readOnly=false,label='Code cell'}){
 const host=useRef(),view=useRef(),props=useRef(),editability=useRef(new Compartment());props.current={onChange,onRun,onSave};
 useEffect(()=>{const v=new EditorView({parent:host.current,state:EditorState.create({doc:value,extensions:[history(),autocompletion(),closeBrackets(),bracketMatching(),indentOnInput(),language==='python'?python():language==='markdown'?markdown():[],syntaxHighlighting(colors),EditorView.lineWrapping,...(file?[lineNumbers(),highlightActiveLine(),foldGutter()]:[]),editability.current.of([EditorState.readOnly.of(readOnly),EditorView.editable.of(!readOnly)]),EditorView.contentAttributes.of({'aria-label':label,'spellcheck':'false','autocorrect':'off','autocapitalize':'off'}),keymap.of([{key:'Shift-Enter',run:()=>{props.current.onRun?.();return true}},{key:'Mod-s',run:()=>{props.current.onSave?.();return true}},...closeBracketsKeymap,...completionKeymap,...defaultKeymap,...historyKeymap,...searchKeymap,indentWithTab]),EditorView.updateListener.of(update=>{if(update.docChanged)props.current.onChange?.(update.state.doc.toString())}),EditorView.theme({'&':{backgroundColor:'transparent',fontSize:'13px'},'.cm-content':{fontFamily:'ui-monospace, SFMono-Regular, Menlo, monospace',padding:file?'18px 0':'18px 20px',minHeight:file?'100%':'56px',lineHeight:'1.85'},'.cm-scroller':{fontFamily:'inherit',overflow:'auto'},'.cm-gutters':{background:'transparent',color:'var(--faint)',border:'none',padding:'0 8px'},'.cm-activeLine':{background:'color-mix(in srgb, var(--accent-soft) 45%, transparent)'},'.cm-activeLineGutter':{background:'transparent'},'.cm-cursor':{borderLeftColor:'var(--accent)'},'.cm-selectionBackground, &.cm-focused .cm-selectionBackground':{background:'var(--accent-soft)'},'&.cm-focused':{outline:'none'}})]})});view.current=v;return()=>{v.destroy();view.current=null}},[language,file,label]);
 useEffect(()=>{view.current?.dispatch({effects:editability.current.reconfigure([EditorState.readOnly.of(readOnly),EditorView.editable.of(!readOnly)])})},[readOnly]);
 useEffect(()=>{const v=view.current;if(v&&value!==v.state.doc.toString())v.dispatch({changes:{from:0,to:v.state.doc.length,insert:value}})},[value]);
 return <div className={'lab-editor '+(file?'lab-editor-file':'')} ref={host}/>;
}
