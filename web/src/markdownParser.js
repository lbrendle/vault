import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import mark from 'markdown-it-mark';
import texmath from 'markdown-it-texmath';
import katex from 'katex';
import {parse, stringify} from 'yaml';
export const md=new MarkdownIt({html:true,linkify:true,breaks:true,typographer:false}).use(footnote).use(taskLists).use(mark).use(texmath,{engine:katex,delimiters:'dollars',katexOptions:{trust:false,throwOnError:false}});
md.inline.ruler.before('link','wiki',(state,silent)=>{
 const rest=state.src.slice(state.pos),m=/^(!?)\[\[([^\]\n]+)\]\]/.exec(rest);if(!m)return false;
 if(!silent){const token=state.push('html_inline','',0);const [target,...alias]=m[2].replace(/\\\|/g,'|').split('|');const label=alias.join('|')||target;token.content=`<${m[1]?'span':'a'} class="${m[1]?'embed':'wikilink'}" data-wiki="${md.utils.escapeHtml(target)}" ${m[1]?'data-embed="true"':'href="#"'}>${md.utils.escapeHtml(label)}</${m[1]?'span':'a'}>`;}
 state.pos+=m[0].length;return true;
});
const fence=md.renderer.rules.fence.bind(md.renderer.rules);
md.renderer.rules.fence=(tokens,i,options,env,self)=> tokens[i].info.trim()==='mermaid'?`<pre class="mermaid">${md.utils.escapeHtml(tokens[i].content)}</pre>`:fence(tokens,i,options,env,self);
export function frontmatter(content=''){
 const m=/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(content);
 if(!m)return {properties:{},body:content,raw:''};
 try{return {properties:parse(m[1])||{},body:content.slice(m[0].length),raw:m[1]}}catch(error){return {properties:{},body:content,raw:m[1],error:error.message}}
}
export function updateProperties(content,properties){const parsed=frontmatter(content);if(parsed.error)throw new Error('Fix the YAML syntax in source mode before editing properties.');return '---\n'+stringify(properties).trimEnd()+'\n---\n\n'+parsed.body.replace(/^\n+/,'');}

export function parseMarkdown(content){const {body}=frontmatter(content),env={},tokens=md.parse(body,env);let task=0;for(const token of tokens)for(const child of token.children||[])if(child.type==='html_inline'&&child.content.includes('task-list-item-checkbox'))child.content=child.content.replace('<input ',`<input data-task-source="${task++}" `);return {tokens,env}}
export function markdownHTML(content){const {tokens,env}=parseMarkdown(content);return md.renderer.render(tokens,md.options,env)}
export function markdownSections(content,budget=16000){
 const {tokens,env}=parseMarkdown(content),sections=[];let start=0,depth=0,characters=0,lines=0,headings=[];
 for(let i=0;i<tokens.length;i++){const token=tokens[i];
  if(depth===0&&['fence','code_block'].includes(token.type)&&token.info.trim()!=='mermaid'&&token.content.length>budget*2){
   if(i>start)sections.push({start,end:i,characters,lines,headings});
   for(let from=0;from<token.content.length;){let to=Math.min(token.content.length,from+budget);if(to<token.content.length){const newline=token.content.lastIndexOf('\n',to);if(newline>from+budget/2)to=newline+1;else if(/[\uD800-\uDBFF]/.test(token.content[to-1]))to--}sections.push({start:i,end:i+1,slice:[from,to],codeSegment:from===0?'first':to===token.content.length?'last':'middle',characters:to-from,lines:token.content.slice(from,to).split('\n').length,headings:[]});from=to}
   start=i+1;characters=0;lines=0;headings=[];continue;
  }
  depth+=token.nesting;characters+=token.content.length;if(token.map)lines=Math.max(lines,token.map[1]-(tokens[start].map?.[0]||0));if(token.type==='footnote_open')headings.push('fn'+(token.meta.id+1));for(const child of token.children||[])if(child.type==='footnote_ref')headings.push('fnref'+(child.meta.id+1)+(child.meta.subId>0?':'+child.meta.subId:''));if(token.type==='heading_open'){const title=(tokens[i+1]?.children||[]).map(c=>['text','code_inline'].includes(c.type)?c.content:'').join('').trim().replace(/\s+/g,' ');headings.push(title)}
  if(depth===0&&(characters>=budget||i===tokens.length-1)){sections.push({start,end:i+1,characters,lines,headings});start=i+1;characters=0;lines=0;headings=[]}
 }
 return {sections,render:index=>{const section=sections[index];if(!section)throw Error('Invalid document section');const batch=tokens.slice(section.start,section.end);if(section.slice)batch[0]=Object.assign(Object.create(Object.getPrototypeOf(batch[0])),batch[0],{content:batch[0].content.slice(...section.slice)});const html=md.renderer.render(batch,md.options,env);return section.slice?html.replace('<pre',`<pre data-code-segment="${section.codeSegment}"`):html}};
}
