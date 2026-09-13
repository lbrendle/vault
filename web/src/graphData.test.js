import {test} from 'node:test';import assert from 'node:assert/strict';
import {graphBuilder,folderLayout} from './graphData.js';import {fitGraph} from './graphGeometry.js';
test('graph includes all nodes, attachments and links across page boundaries',()=>{
 const b=graphBuilder();for(let page=0;page<8;page++)b.addNodes(Array.from({length:128},(_,i)=>({path:`Research/Note ${page*128+i}.md`,title:`Note ${page*128+i}`})));
 b.addNodes([{path:'Research/Paper.pdf',title:'Paper'},{path:'Elsewhere/Note 999.md',title:'Note 999'}]);
 b.addLinks(Array.from({length:1024},(_,i)=>({source:'Research/Note 0.md',target:`Note ${i}`})));
 b.addLinks([{source:'Research/Note 0.md',target:'Paper.pdf#page=3'},{source:'Research/Note 0.md',target:'../Elsewhere/Note%20999.md'}]);
 const full=b.finish();assert.equal(full.nodes.length,1026);assert.equal(full.edges.length/2,1025);
 const local=b.finish('Research/Note 0.md');assert.equal(local.nodes.length,1026);assert.equal(local.edges.length/2,1025);
 assert.equal(full.nodes[full.edges[1996]].path,'Research/Note 0.md');
});
test('large layout and fit cover 200,000 documents without argument-stack overflow',()=>{
 const nodes=Array.from({length:200000},(_,i)=>({path:`Folder ${Math.floor(i/400)}/Note ${i}.md`,title:`Note ${i}`,index:i}));folderLayout(nodes);
 const t=fitGraph(nodes,1024,740);assert.ok(t.k<.08);for(const n of nodes){assert.ok(Number.isFinite(n.x)&&Number.isFinite(n.y));const x=n.x*t.k+t.x,y=n.y*t.k+t.y;assert.ok(x>=30&&x<=994&&y>=30&&y<=710)}
});

test('connection detail simplifies the overview without losing the original edges',async()=>{
 const {edgeDetailLevels}=await import('./graphData.js');const nodes=Array.from({length:2000},(_,index)=>({index,x:index%50*12,y:Math.floor(index/50)*12})),edges=new Uint32Array(Array.from({length:1999},(_,i)=>[i,i+1]).flat());const levels=edgeDetailLevels(nodes,edges);assert.equal(edges.length,3998);assert.equal(levels.length,2);assert.ok(levels[0].indices.length<edges.length);for(const l of levels)for(const id of l.indices)assert.ok(id<nodes.length);
});
test('constellation layout keeps stable document indices and finite positions',async()=>{
 const {constellationLayout}=await import('./graphLayout.js');const nodes=Array.from({length:2000},(_,index)=>({index,path:`N${index}.md`,title:`N${index}`})),edges=new Uint32Array(Array.from({length:1999},(_,i)=>[0,i+1]).flat());constellationLayout(nodes,edges);nodes.forEach((n,i)=>{assert.equal(n.index,i);assert.ok(Number.isFinite(n.x)&&Number.isFinite(n.y))});
});

test('coincident input nodes settle into a bounded, separated local graph',async()=>{const {constellationLayout}=await import('./graphLayout.js'),nodes=Array.from({length:600},(_,index)=>({index,x:0,y:0,path:`Note ${index}.md`,title:`Note ${index}`})),edges=new Uint32Array(Array.from({length:599},(_,i)=>[i+1,Math.floor(i/3)]).flat());constellationLayout(nodes,edges);assert.ok(fitGraph(nodes,640,800).k>.05);for(const node of nodes)assert.ok(Number.isFinite(node.x)&&Number.isFinite(node.y))});
