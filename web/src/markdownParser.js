import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import mark from 'markdown-it-mark';
import texmath from 'markdown-it-texmath';
import katex from 'katex';
import {parse, parseDocument, stringify, isMap, isScalar} from 'yaml';
export const md=new MarkdownIt({html:true,linkify:true,breaks:true,typographer:false}).use(footnote).use(taskLists).use(mark).use(texmath,{engine:katex,delimiters:'dollars',katexOptions:{trust:false,throwOnError:false}});
// Bare code filenames are local references, even when their extension is a
// real top-level domain (for example .py, .rs, or .sh). Explicit web URLs stay web URLs.
const codePath=/\.(?:py|pyi|ipynb|js|jsx|ts|tsx|swift|c|h|cpp|hpp|rs|go|r|jl|sh|bash|zsh|sql|m|mm|metal|html|css|json|jsonl|toml|yaml|yml)(?:#[^\n]*)?$/i;
md.core.ruler.after('linkify','local_code_links',state=>{
 for(const block of state.tokens)for(let i=0;i<(block.children||[]).length;i++){
  const token=block.children[i],text=block.children[i+1];
  if(token.type==='link_open'&&token.markup==='linkify'&&text?.type==='text'&&codePath.test(text.content)&&! /^(?:[a-z][a-z0-9+.-]*:|\/\/|www\.)/i.test(text.content)){
   token.attrSet('data-wiki',text.content);token.attrSet('href','#');
  }
 }
});
md.inline.ruler.before('link','wiki',(state,silent)=>{
 const rest=state.src.slice(state.pos),m=/^(!?)\[\[([^\]\n]+)\]\]/.exec(rest);if(!m)return false;
 if(!silent){const token=state.push('html_inline','',0);const [target,...alias]=m[2].replace(/\\\|/g,'|').split('|');const label=alias.join('|')||(state.env.chat?target.split('/').pop().replace(/\.md(?=#|$)/i,''):target);token.content=`<${m[1]?'span':'a'} class="${m[1]?'embed':'wikilink'}" data-wiki="${md.utils.escapeHtml(target)}" title="${md.utils.escapeHtml(target)}" ${m[1]?'data-embed="true"':'href="#"'}>${md.utils.escapeHtml(label)}</${m[1]?'span':'a'}>`;}
 state.pos+=m[0].length;return true;
});
// Accept Obsidian-style local document paths containing spaces, including notebooks.
// Never recover a URL or executable scheme as a local path.
md.inline.ruler.before('link','chat_document_link',(state,silent)=>{
 if(state.src[state.pos]!=='['||state.linkLevel>0)return false;
 const labelEnd=md.helpers.parseLinkLabel(state,state.pos,false);
 if(labelEnd<0||state.src[labelEnd+1]!=='(')return false;
 let end=labelEnd+2,depth=1;
 for(;end<state.posMax;end++){
  const char=state.src[end];if(char==='\n')return false;
  if(char==='\\'){end++;continue}if(char==='(')depth++;if(char===')'&&--depth===0)break;
 }
 if(depth!==0)return false;
 const target=state.src.slice(labelEnd+2,end).trim();
 if(!/\s/.test(target)||/[<>"\x00-\x1f]/.test(target)||/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(target)||! /\.(?:md|markdown|pdf|txt|canvas|base|py|pyi|ipynb|js|jsx|ts|tsx|swift|c|h|cpp|hpp|rs|go|r|jl|sh|bash|zsh|sql|m|mm|metal|html|css|json|jsonl|toml|yaml|yml)(?:#[^\n]*)?$/i.test(target))return false;
 if(!silent){
  const token=state.push('html_inline','',0),label=state.src.slice(state.pos+1,labelEnd);
  token.content=`<a class="wikilink" data-wiki="${md.utils.escapeHtml(target)}" href="#">${md.utils.escapeHtml(label)}</a>`;
 }
 state.pos=end+1;return true;
});
const inlineCode=md.renderer.rules.code_inline;
md.renderer.rules.code_inline=(tokens,i,options,env,self)=>{
 const text=tokens[i].content;
 if(codePath.test(text)&&!/[\s:="'<>|(){}]/.test(text)){
  const target=md.utils.escapeHtml(text);
  return `<a class="wikilink code-file-link" data-wiki="${target}" href="#"><code>${target}</code></a>`;
 }
 if(env.chat&&(/^\[\[[^\]\n]+\]\]$/.test(text)||/^\[[^\]\n]+\]\([^\n]+\)$/.test(text))){
  const rendered=md.renderInline(text,env);
  if(/^<a\b/.test(rendered)&&rendered.endsWith('</a>'))return rendered;
 }
 return inlineCode(tokens,i,options,env,self);
};
const fence=md.renderer.rules.fence.bind(md.renderer.rules);
md.renderer.rules.fence=(tokens,i,options,env,self)=> tokens[i].info.trim()==='mermaid'?`<pre class="mermaid">${md.utils.escapeHtml(tokens[i].content)}</pre>`:fence(tokens,i,options,env,self);
export function frontmatter(content=''){
 const m=/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(content);
 if(!m)return {properties:{},body:content,raw:''};
 try{return {properties:parse(m[1])||{},body:content.slice(m[0].length),raw:m[1]}}catch(error){return {properties:{},body:content,raw:m[1],error:error.message}}
}
// Rewrites only the properties that changed, by splicing the frontmatter's own text. Every other key keeps
// its source exactly, so `id: 007`, `version: 1.10`, long numbers, quoting, order and comments survive an edit
// elsewhere. Frontmatter that is not a plain block of `key: value` lines is regenerated whole, as before.
export function updateProperties(content,properties){
 const parsed=frontmatter(content);if(parsed.error)throw new Error('Fix the YAML syntax in source mode before editing properties.');
 properties=Object.fromEntries(Object.entries(properties).filter(([,value])=>value!==undefined)); // an undefined value means the property is absent
 const before=parsed.properties,document=parseDocument(parsed.raw),map=document.contents,write=(key,value)=>stringify({[key]:value}).trimEnd();
 const spliceable=!document.errors.length&&isMap(map)&&!map.flow&&map.items.every(pair=>isScalar(pair.key)&&pair.key.range);
 let text=parsed.raw;
 if(!spliceable)text=stringify(properties);
 else{
  const edits=[];
  for(const pair of map.items){
   const key=String(pair.key.value),start=pair.key.range[0];let end=pair.value?.range?pair.value.range[2]:pair.key.range[2];
   if(text[end-1]!=='\n'){const newline=text.indexOf('\n',end);end=newline<0?text.length:newline+1}
   if(!(key in properties))edits.push([start,end,'']);
   else if(JSON.stringify(before[key])!==JSON.stringify(properties[key]))edits.push([start,end,write(key,properties[key])+(text[end-1]==='\n'?'\n':'')]);
  }
  for(const [start,end,replacement] of edits.reverse())text=text.slice(0,start)+replacement+text.slice(end);
  for(const [key,value] of Object.entries(properties))if(!(key in before))text=(text.trimEnd()?text.trimEnd()+'\n':'')+write(key,value);
 }
 return '---\n'+text.trimEnd()+'\n---\n\n'+parsed.body.replace(/^\n+/,'');
}
// Sets or clears the checkbox on one source line (0-based, counted from the top of the file).
// A line that is not a task leaves the content untouched.
export function toggleTask(content,line,checked){
 const lines=content.split('\n'),task=/^(\s*(?:>\s*)*(?:[-*+]|\d+[.)])\s+)\[[ xX]\]/;
 if(!Number.isInteger(line)||line<0||line>=lines.length||!task.test(lines[line]))return content;
 lines[line]=lines[line].replace(task,(match,prefix)=>prefix+'['+(checked?'x':' ')+']');
 return lines.join('\n');
}

export function parseMarkdown(content,options={}){const {body}=frontmatter(content),env={chat:options.chat===true},tokens=md.parse(body,env);
 // Each task checkbox carries the source line it was written on (see toggleTask), not its position among
 // rendered checkboxes: fenced examples, numbered and quoted tasks make those two counts disagree.
 const firstLine=content.slice(0,content.length-body.length).split('\n').length-1;
 for(const token of tokens)for(const child of token.children||[])if(child.type==='html_inline'&&child.content.includes('task-list-item-checkbox'))child.content=child.content.replace('<input ',`<input data-task-source="${firstLine+(token.map?token.map[0]:-1)}" `);
 return {tokens,env}}
export function markdownHTML(content,options){const {tokens,env}=parseMarkdown(content,options);return md.renderer.render(tokens,md.options,env)}
export function markdownSections(content,budget=16000,options){
 const {tokens,env}=parseMarkdown(content,options),sections=[];let start=0,depth=0,characters=0,lines=0,headings=[];
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
