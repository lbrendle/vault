import DOMPurify from 'dompurify';
import {markdownHTML} from './markdownParser';
export {frontmatter,updateProperties} from './markdownParser';
export function markdownFragment(html){
 const fragment=DOMPurify.sanitize(html,{RETURN_DOM_FRAGMENT:true,FORBID_TAGS:['iframe','form','object','embed','style','script'],ADD_ATTR:['data-wiki','data-embed'],ALLOW_DATA_ATTR:true});
 let taskIndex=0;
 for(const input of fragment.querySelectorAll('input')){if(input.type==='checkbox'&&input.classList.contains('task-list-item-checkbox')){input.disabled=false;input.dataset.task=String(input.dataset.taskSource??taskIndex++);input.setAttribute('aria-label',input.parentElement.textContent.trim());}else input.remove();}
 for(const img of fragment.querySelectorAll('img')){const src=img.getAttribute('src')||'';if(/^(https?:|\/\/)/i.test(src)){img.replaceWith(document.createTextNode('[Remote image: '+(img.alt||src)+']'));}else{img.setAttribute('data-image',src);img.removeAttribute('src');}}
 for(const h of fragment.querySelectorAll('h1,h2,h3,h4,h5,h6'))h.id=h.textContent.trim().replace(/\s+/g,' ');
 // Tables keep their column structure, but never set the width of the page.
 for(const table of fragment.querySelectorAll('table')){const viewport=document.createElement('div');viewport.className='markdown-table-scroll';viewport.tabIndex=0;viewport.setAttribute('role','region');viewport.setAttribute('aria-label',table.querySelector('caption')?.textContent.trim()||'Scrollable table');table.replaceWith(viewport);viewport.append(table);}
 for(const b of fragment.querySelectorAll('blockquote')){const p=b.querySelector('p');const match=p?.textContent.match(/^\[!([^\]]+)\]([+-])?\s*/);if(match){b.classList.add('callout');const label=document.createElement('strong');label.className='callout-label';label.textContent=match[1];b.prepend(label);p.innerHTML=p.innerHTML.replace(/^\[![^\]]+\][+-]?\s*/,'');}}
 return fragment;
}

export const renderFragment=content=>markdownFragment(markdownHTML(content));
export function render(content){const box=document.createElement('div');box.append(renderFragment(content));return box.innerHTML}
