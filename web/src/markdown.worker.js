import {markdownSections} from './markdownParser';
let document;
self.onmessage=({data})=>{try{
 if(data.kind==='prepare'){document=markdownSections(data.content,16000,{chat:data.chat});self.postMessage({kind:'prepared',sections:document.sections.map(({characters,lines,headings})=>({characters,lines,headings}))})}
 if(data.kind==='render'&&document)self.postMessage({kind:'section',index:data.index,html:document.render(data.index)})
}catch(error){self.postMessage({kind:'error',message:error.message})}};
