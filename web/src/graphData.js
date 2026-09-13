// Link resolution and layout run in a worker, away from typing and navigation.
export function graphBuilder(){
 const nodes=[],paths=new Map(),titles=new Map(),pairs=[],seen=new Set();
 const normalize=p=>{const out=[];for(const bit of p.split('/')){if(bit==='..')out.pop();else if(bit&&bit!=='.')out.push(bit)}return out.join('/').normalize('NFC')};
 function addNodes(items){for(const item of items){const path=item.path.normalize('NFC');if(paths.has(path))continue;const index=nodes.length;paths.set(path,index);nodes.push({path:item.path,title:item.title,index,x:0,y:0});const title=item.title.toLocaleLowerCase();if(!titles.has(title))titles.set(title,index)}}
 function resolve(target,source){let clean=target;try{clean=decodeURIComponent(clean)}catch{}clean=clean.split('#')[0].split('|')[0];if(!clean)return paths.get(source);if(/^[a-z][\w+.-]*:\/\//i.test(clean))return;const parent=source.slice(0,Math.max(0,source.lastIndexOf('/'))),relative=parent?parent+'/'+clean:clean;for(const p of [relative,relative+'.md',clean,clean+'.md']){const found=paths.get(normalize(p));if(found!==undefined)return found}return titles.get(clean.split('/').at(-1).replace(/\.[^.]+$/,'').toLocaleLowerCase())}
 function addLinks(items){for(const link of items){const from=paths.get(link.source.normalize('NFC'));if(from===undefined)continue;const to=resolve(link.target,link.source.normalize('NFC'));if(to===undefined||from===to)continue;const key=Math.min(from,to)*nodes.length+Math.max(from,to);if(seen.has(key))continue;seen.add(key);pairs.push(from,to)}}
 function finish(path=''){
  if(!path)return{nodes,edges:new Uint32Array(pairs)};
  const center=paths.get(path.normalize('NFC')),keep=new Set(center===undefined?[]:[center]);
  for(let i=0;i<pairs.length;i+=2){if(pairs[i]===center)keep.add(pairs[i+1]);if(pairs[i+1]===center)keep.add(pairs[i])}
  const local=[],mapping=new Map();for(const i of keep){mapping.set(i,local.length);local.push({...nodes[i],index:local.length})}
  const edges=[];for(let i=0;i<pairs.length;i+=2)if(keep.has(pairs[i])&&keep.has(pairs[i+1]))edges.push(mapping.get(pairs[i]),mapping.get(pairs[i+1]));
  return{nodes:local,edges:new Uint32Array(edges)};
 }
 return{addNodes,addLinks,finish,get count(){return nodes.length}};
}
export function folderLayout(nodes){
 const folders=new Map();for(const n of nodes){const folder=n.path.slice(0,Math.max(0,n.path.lastIndexOf('/')));if(!folders.has(folder))folders.set(folder,[]);folders.get(folder).push(n)}
 const groups=[...folders].sort((a,b)=>a[0].localeCompare(b[0])).map(([name,items])=>({name,items,weight:items.length+8}));
 const total=groups.reduce((s,g)=>s+g.weight,0),side=Math.sqrt(Math.max(1,total))*34;
 function place(list,x,y,w,h,weight){
  if(!list.length)return;
  if(list.length===1){const items=list[0].items.sort((a,b)=>a.path.localeCompare(b.path));items.forEach((n,i)=>{const r=Math.sqrt((i+.5)/items.length)*.88,a=i*2.3999632297;n.x=x+w/2+Math.cos(a)*r*w/2;n.y=y+h/2+Math.sin(a)*r*h/2});return}
  let sum=0,split=0;while(split<list.length-1&&sum<weight/2){sum+=list[split++].weight}const fraction=sum/weight;
  if(w>=h){place(list.slice(0,split),x,y,w*fraction,h,sum);place(list.slice(split),x+w*fraction,y,w*(1-fraction),h,weight-sum)}else{place(list.slice(0,split),x,y,w,h*fraction,sum);place(list.slice(split),x,y+h*fraction,w,h*(1-fraction),weight-sum)}
 }
 place(groups,-side/2,-side/2,side,side,total);return nodes;
}
// At overview scale, nearby endpoints share one visible connection. Every edge
// remains in the full buffer and is revealed on zoom or node selection.
export function edgeDetailLevels(nodes,edges){
 if(nodes.length<=1600)return[];
 return[{cell:1024,below:.12},{cell:256,below:.35}].map(({cell,below})=>{
  const cells=new Map(),ids=new Uint32Array(nodes.length);for(const n of nodes){const key=Math.floor(n.x/cell)+','+Math.floor(n.y/cell);if(!cells.has(key))cells.set(key,cells.size);ids[n.index]=cells.get(key)}
  const seen=new Set(),indices=[];for(let i=0;i<edges.length;i+=2){const a=ids[edges[i]],b=ids[edges[i+1]];if(a===b)continue;const key=Math.min(a,b)*cells.size+Math.max(a,b);if(seen.has(key))continue;seen.add(key);indices.push(edges[i],edges[i+1])}return{below,indices:new Uint32Array(indices)};
 });
}
