import {api} from './api.js';
let queue=Promise.resolve();
export function labApi(method,args={}){if(['labCancel','labRemoteCancel'].includes(method)||!method.startsWith('lab'))return api(method,args);const result=queue.catch(()=>{}).then(()=>api(method,args));queue=result;return result}
const codeExtensions=new Set(['py','pyi','ipynb','js','jsx','ts','tsx','swift','c','h','cpp','hpp','rs','go','r','jl','sh','bash','zsh','sql','m','mm','metal','html','css','json','jsonl','toml','yaml','yml']);
export function isLabFile(path=''){return codeExtensions.has(path.split('.').pop().toLowerCase())}
export function labTargetForPath(path){
 const parts=path.split('/');
 if(path.startsWith('/')||parts.some(p=>!p||p==='..'||p==='.')||!isLabFile(path))throw Error('Choose a code file inside this vault.');
 const file=parts.pop();
 if(parts[0]==='Labs'&&parts.length>=2)return {project:parts[1],path:[...parts.slice(2),file].join('/')};
 return {project:'@/'+parts.join('/'),path:file};
}
export function labProjectLabel(project){return project.startsWith('@/')?project.slice(2).split('/').pop()||'Vault':project}
export function labVaultPath(project,path){const base=project.startsWith('@/')?project.slice(2):'Labs/'+project;return [base,path].filter(Boolean).join('/')}
