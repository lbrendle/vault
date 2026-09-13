import {graphMetrics} from './graphLabels';
// Every original document and edge remains
// in GPU storage; a topology-based overview expands smoothly into full detail.
export function createGraphRenderer(canvas,nodes,edges,levels=[],overview=null){
 const gl=canvas.getContext('webgl',{alpha:true,antialias:true,depth:false,powerPreference:'low-power'});
 if(!gl||!gl.getExtension('OES_element_index_uint'))return null;
 const shaders=[];
 function shader(type,source){const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(s));shaders.push(s);return s}
 const program=gl.createProgram();gl.attachShader(program,shader(gl.VERTEX_SHADER,'attribute vec2 position; uniform vec2 viewport; uniform vec3 camera; uniform float pointSize; void main(){vec2 p=(position*camera.z+camera.xy)/viewport;gl_Position=vec4(p.x*2.0-1.0,1.0-p.y*2.0,0,1);gl_PointSize=pointSize;}'));gl.attachShader(program,shader(gl.FRAGMENT_SHADER,'precision mediump float; uniform vec4 color; uniform bool points;void main(){if(points&&distance(gl_PointCoord,vec2(.5))>.5)discard;gl_FragColor=color;}'));gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(program));
 const buffers=[];
 function buffer(target,data,dynamic=false){const b=gl.createBuffer();buffers.push(b);gl.bindBuffer(target,b);gl.bufferData(target,data,dynamic?gl.DYNAMIC_DRAW:gl.STATIC_DRAW);return b}
 function geometry(items,indices){const positions=new Float32Array(items.length*2);items.forEach((n,i)=>{positions[i*2]=n.x;positions[i*2+1]=n.y});return{vertices:buffer(gl.ARRAY_BUFFER,positions,true),indices:buffer(gl.ELEMENT_ARRAY_BUFFER,indices),count:items.length,edgeCount:indices.length}}
 const full=geometry(nodes,edges),coarse=overview?geometry(overview.nodes,overview.edges):null;
 const groupPoints=overview?[{items:overview.nodes.filter(n=>n.count>1),alpha:1,size:3.2},{items:overview.nodes.filter(n=>n.count===1),alpha:.2,size:1.8}].map(g=>({...g,buffer:buffer(gl.ELEMENT_ARRAY_BUFFER,new Uint32Array(g.items.map(n=>n.index)))})):[];
 const visibleBuffer=buffer(gl.ELEMENT_ARRAY_BUFFER,new Uint32Array(),true);
 const detailBuffers=levels.map(level=>({below:level.below,buffer:buffer(gl.ELEMENT_ARRAY_BUFFER,level.indices),count:level.indices.length}));
 const attribute=gl.getAttribLocation(program,'position'),u=Object.fromEntries(['viewport','camera','pointSize','color','points'].map(k=>[k,gl.getUniformLocation(program,k)]));
 gl.enable(gl.BLEND);gl.blendFuncSeparate(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA,gl.ONE,gl.ONE_MINUS_SRC_ALPHA);
 const rgb=hex=>{const value=hex.trim().replace('#','');return[parseInt(value.slice(0,2),16)/255,parseInt(value.slice(2,4),16)/255,parseInt(value.slice(4,6),16)/255]};
 return{
  draw(t,width,height,ratio,palette,visibleEdges=null){
   if(gl.isContextLost())return;gl.viewport(0,0,canvas.width,canvas.height);gl.clear(gl.COLOR_BUFFER_BIT);gl.useProgram(program);gl.enableVertexAttribArray(attribute);gl.uniform2f(u.viewport,width,height);gl.uniform3f(u.camera,t.x,t.y,t.k);const color=rgb(palette.accent),detail=detailBuffers.find(level=>t.k<level.below),blend=coarse?Math.max(0,Math.min(1,(t.k-.045)/.065)):1;
   function layer(g,alpha,pointSize,indexBuffer=g.indices,edgeCount=g.edgeCount){if(alpha<=0)return;gl.bindBuffer(gl.ARRAY_BUFFER,g.vertices);gl.vertexAttribPointer(attribute,2,gl.FLOAT,false,0,0);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,indexBuffer);gl.uniform1f(u.pointSize,pointSize*ratio);gl.uniform1i(u.points,0);gl.uniform4f(u.color,...color,.065*alpha);gl.drawElements(gl.LINES,edgeCount,gl.UNSIGNED_INT,0);gl.uniform1i(u.points,1);if(g===coarse){for(const points of groupPoints){gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,points.buffer);gl.uniform1f(u.pointSize,points.size*ratio);gl.uniform4f(u.color,...color,.75*alpha*points.alpha);gl.drawElements(gl.POINTS,points.items.length,gl.UNSIGNED_INT,0)}}else{gl.uniform4f(u.color,...color,.75*alpha);gl.drawArrays(gl.POINTS,0,g.count)}}
   if(visibleEdges){gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,visibleBuffer);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,visibleEdges,gl.DYNAMIC_DRAW)}
   if(coarse)layer(coarse,1-blend,3.4);layer(full,blend,graphMetrics(t.k).nodeDiameter,visibleEdges?visibleBuffer:detail?.buffer||full.indices,visibleEdges?visibleEdges.length:detail?.count??full.edgeCount);
  },
  move(n){gl.bindBuffer(gl.ARRAY_BUFFER,full.vertices);gl.bufferSubData(gl.ARRAY_BUFFER,n.index*8,new Float32Array([n.x,n.y]))},
  destroy(){buffers.forEach(b=>gl.deleteBuffer(b));gl.deleteProgram(program);shaders.forEach(s=>gl.deleteShader(s))}
 };
}
