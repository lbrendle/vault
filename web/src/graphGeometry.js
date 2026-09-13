export const clampScale=k=>Math.max(.00001,Math.min(12,k));
export const worldPoint=(p,t)=>({x:(p.x-t.x)/t.k,y:(p.y-t.y)/t.k});
export function zoomAt(t,point,factor){const k=clampScale(t.k*factor),w=worldPoint(point,t);return {k,x:point.x-w.x*k,y:point.y-w.y*k}}
export function fitGraph(nodes,width,height){if(!nodes.length)return{x:width/2,y:height/2,k:1};let l=Infinity,r=-Infinity,t=Infinity,b=-Infinity;for(const n of nodes){l=Math.min(l,n.x||0);r=Math.max(r,n.x||0);t=Math.min(t,n.y||0);b=Math.max(b,n.y||0)}l-=30;r+=30;t-=30;b+=30;const k=Math.min(1.7,clampScale(Math.min(Math.max(1,width-80)/(r-l),Math.max(1,height-80)/(b-t))));return{k,x:width/2-(l+r)*k/2,y:height/2-(t+b)*k/2}}

// A connection entirely outside the viewport cannot add useful local context.
// Keep every edge incident to a visible node, including its off-screen neighbors.
export function viewportEdges(adjacency,visibleIds){const visible=new Set(visibleIds),indices=[];for(const id of visibleIds)for(const next of adjacency[id])if(id<next||!visible.has(next))indices.push(id,next);return new Uint32Array(indices)}
