import {graphBuilder,edgeDetailLevels} from './graphData';
import {constellationLayout} from './graphLayout';
const builder=graphBuilder();
self.onmessage=({data})=>{try{
 if(data.kind==='nodes'){builder.addNodes(data.items);return}
 if(data.kind==='links'){builder.addLinks(data.items);return}
 if(data.kind==='finish'){
  const {nodes,edges}=builder.finish(data.path);const {overview}=constellationLayout(nodes,edges);
  const levels=edgeDetailLevels(nodes,edges);self.postMessage({nodes,edges,levels,overview},[edges.buffer,...levels.map(l=>l.indices.buffer),...(overview?[overview.edges.buffer]:[])]);
 }
}catch(error){self.postMessage({error:error.message})}};
