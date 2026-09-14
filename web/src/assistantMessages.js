export const assistantName = provider => ({local:'Local model',codex:'Codex',claude:'Claude Code'}[provider] || provider);

export function assistantText(result) {
 return (result?.outputs || []).map(output => {
  if(output.output_type==='stream' && output.name!=='stderr')return Array.isArray(output.text)?output.text.join(''):output.text || '';
  const text=output.data?.['text/plain'];
  return Array.isArray(text)?text.join(''):text || '';
 }).join('\n').trim();
}

export function assistantConversation(history,project,provider,target) {
 return history.filter(entry=>entry.project===project && entry.provider===provider && entry.target===target);
}

export function assistantFileContext(file) {
 if(!file?.content)return '';
 let content=file.content;
 if(/\.ipynb$/i.test(file.path)) {
  try {content=JSON.parse(content).cells.map(cell=>`[${cell.cell_type}]\n${Array.isArray(cell.source)?cell.source.join(''):cell.source || ''}`).join('\n\n');}
  catch {return '';}
 }
 return content.length>6000?content.slice(0,6000)+'\n[File excerpt ends here]':content;
}

export function assistantMessages(prompt,history,file,includeFile) {
 const context=includeFile?assistantFileContext(file):'';
 const current={role:'user',content:prompt.slice(0,4000)+(context?`\n\nAttached file: ${file.path}\n<file_context>\n${context}\n</file_context>`:'')};
 let remaining=12000-current.content.length;
 const prior=[];
 for(const entry of history.filter(e=>e.result?.status==='ok').slice(-4).reverse()) {
  const question=entry.prompt.slice(0,1500),answer=assistantText(entry.result).slice(0,2500);
  if(!answer || question.length+answer.length>remaining)break;
  prior.unshift({role:'user',content:question},{role:'assistant',content:answer});
  remaining-=question.length+answer.length;
 }
 return [...prior,current];
}
