import {forceSimulation,forceLink,forceManyBody,forceCenter,forceCollide} from 'd3-force';

// Coarsen by graph traversal, lay out connected communities, then arrange every
// original document inside its community. No force loop runs on the UI thread.
export function constellationLayout(nodes,edges){
 const n=nodes.length;if(!n)return {nodes,overview:null};
 const adjacency=Array.from({length:n},()=>[]);for(let i=0;i<edges.length;i+=2){adjacency[edges[i]].push(edges[i+1]);adjacency[edges[i+1]].push(edges[i])}
 if(n<=1600){nodes.forEach((node,i)=>{const angle=i*2.3999632297,radius=Math.sqrt(i+.5)*45;node.x=Math.cos(angle)*radius;node.y=Math.sin(angle)*radius});const links=[];for(let i=0;i<edges.length;i+=2)links.push({source:edges[i],target:edges[i+1]});const simulation=forceSimulation(nodes).force('link',forceLink(links).id(x=>x.index).distance(90)).force('charge',forceManyBody().strength(-100)).force('center',forceCenter()).force('collide',forceCollide(22).iterations(2)).stop();simulation.tick(140);return {nodes,overview:null}}
 const roots=Array.from({length:n},(_,i)=>i).sort((a,b)=>adjacency[b].length-adjacency[a].length||a-b),visited=new Uint8Array(n),membership=new Uint32Array(n),queue=new Uint32Array(n),groups=[];
 for(const root of roots){if(visited[root])continue;let head=0,tail=1;queue[0]=root;visited[root]=1;
  while(head<tail){const id=queue[head++];for(const next of adjacency[id])if(!visited[next]){visited[next]=1;queue[tail++]=next}}
  for(let start=0;start<tail;start+=256){const ids=Array.from(queue.subarray(start,Math.min(start+256,tail))),g={id:groups.length,ids,r:Math.sqrt(ids.length)*30,x:0,y:0,links:[]};for(const id of ids)membership[id]=g.id;groups.push(g)}
 }
 const between=new Map();for(let i=0;i<edges.length;i+=2){const a=edges[i],b=edges[i+1],ga=membership[a],gb=membership[b];if(ga===gb){groups[ga].links.push({source:nodes[a],target:nodes[b]});continue}const low=Math.min(ga,gb),high=Math.max(ga,gb),key=low*groups.length+high;if(between.has(key))between.get(key).weight++;else between.set(key,{source:low,target:high,weight:1})}
 const linked=new Set();for(const e of between.values()){linked.add(e.source);linked.add(e.target)}
 const active=groups.filter(g=>linked.has(g.id)),links=[...between.values()];
 if(active.length){active.forEach((group,i)=>{const angle=i*2.3999632297,radius=Math.sqrt(i+.5)*800;group.x=Math.cos(angle)*radius;group.y=Math.sin(angle)*radius});const simulation=forceSimulation(active).force('link',forceLink(links).id(g=>g.id).distance(e=>e.source.r+e.target.r+200).strength(e=>Math.min(.16,.025*Math.sqrt(e.weight)))).force('charge',forceManyBody().strength(-1600)).force('center',forceCenter()).force('collide',forceCollide(g=>g.r+85).iterations(2)).stop();simulation.tick(180)}
 // Components with no outward connections remain visible in a separate orbit.
 let outer=0;for(const g of active)outer=Math.max(outer,Math.hypot(g.x,g.y)+g.r);let mass=0,orbit=0;
 for(const g of groups)if(!linked.has(g.id)){mass+=g.ids.length+12;const seed=++orbit*12.9898,u=Math.abs(Math.sin(seed)*43758.5453)%1,a=orbit*2.3999632297,r=Math.max(1500,outer*.85)*Math.sqrt(u);g.x=Math.cos(a)*r;g.y=Math.sin(a)*r}
 for(const g of groups){
  g.ids.sort((a,b)=>adjacency[b].length-adjacency[a].length||a-b);
  const members=g.ids.map((id,i)=>{const node=nodes[id],a=i*2.3999632297,r=i?g.r*.8*Math.sqrt(i/g.ids.length):0;node.x=g.x+Math.cos(a)*r;node.y=g.y+Math.sin(a)*r;return node});
  if(members.length>1){const sim=forceSimulation(members).force('link',forceLink(g.links).id(x=>x.index).distance(75).strength(.25)).force('charge',forceManyBody().strength(-75)).force('center',forceCenter(g.x,g.y)).force('collide',forceCollide(22)).stop();sim.tick(28)}
 }
 nodes.forEach((node,index)=>{node.index=index});
 const overviewNodes=groups.map(g=>({x:g.x,y:g.y,count:g.ids.length,title:nodes[g.ids[0]].title,index:g.id,linked:linked.has(g.id),isGroup:true}));
 // The overview keeps a spanning forest and the strongest local relations.
 // Full document-level edges remain unchanged for detailed exploration.
 const parent=Uint32Array.from(groups,(_,i)=>i),degree=new Uint8Array(groups.length),overviewEdges=[];
 const root=id=>{while(parent[id]!==id){parent[id]=parent[parent[id]];id=parent[id]}return id};
 for(const e of [...links].sort((a,b)=>b.weight-a.weight)){const a=e.source.id,b=e.target.id,ra=root(a),rb=root(b),connect=ra!==rb;if(connect)parent[ra]=rb;if(connect||degree[a]<3&&degree[b]<3){overviewEdges.push(a,b);degree[a]++;degree[b]++}}
 return {nodes,overview:{nodes:overviewNodes,edges:new Uint32Array(overviewEdges)}};
}
