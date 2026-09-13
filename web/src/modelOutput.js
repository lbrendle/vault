// Keep streamed model control tokens out of the answer, including partial tokens.
export function splitModelOutput(raw) {
 let content=raw,reasoning='',thinking=false;
 const qwen=content.indexOf('<think>');
 if(qwen>=0){const end=content.indexOf('</think>',qwen+7);reasoning=content.slice(qwen+7,end<0?undefined:end);thinking=end<0;content=content.slice(0,qwen)+(end<0?'':content.slice(end+8))}
 const gemma=content.match(/<\|channel>(thought|analysis)\n?/);
 if(gemma){const start=gemma.index,end=content.indexOf('<channel|>',start+gemma[0].length);reasoning+=content.slice(start+gemma[0].length,end<0?undefined:end);thinking=end<0;content=content.slice(0,start)+(end<0?'':content.slice(end+10))}
 content=content.replace(/<\|channel>final\n?/g,'').replace(/<channel\|>|<turn\|>|<\|im_end\|>/g,'');
 for(const marker of ['<think>','</think>','<|channel>thought','<|channel>final','<channel|>','<turn|>','<|im_end|>']) {
  for(let n=1;n<marker.length;n++){if(content.endsWith(marker.slice(0,n))){content=content.slice(0,-n);break}}
 }
 return {content,reasoning,thinking};
}
