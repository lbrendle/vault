// Keep the visible page window stable when sync changes the directory underneath it.
export class FileBrowser {
 constructor(list,onChange,onError){this.list=list;this.onChange=onChange;this.onError=onError;this.generation=0;this.request=0;this.path='';this.pages=1;this.rows=[];this.more=false;this.busy=false;this.active=false;this.timer=null;}
 publish(){this.onChange({rows:this.rows,more:this.more,busy:this.busy});}
 reset(path,active=true){clearTimeout(this.timer);this.generation++;this.request++;this.path=path;this.active=active;this.pages=1;this.rows=[];this.more=false;this.busy=false;this.publish();if(active)return this.refresh();}
 async refresh(){
  if(!this.active)return;
  const generation=this.generation,request=++this.request,path=this.path,pages=this.pages;
  this.busy=true;this.publish();
  try{
   const batches=await Promise.all(Array.from({length:pages},(_,page)=>this.list({path,offset:page*200})));
   if(generation!==this.generation||request!==this.request)return;
   this.rows=batches.flat();this.more=batches.at(-1).filter(row=>!row.directory).length===200;
  }catch(error){if(generation===this.generation&&request===this.request)this.onError(error)}
  finally{if(generation===this.generation&&request===this.request){this.busy=false;this.publish();}}
 }
 async loadMore(){
  if(!this.active||this.busy||!this.more)return;
  this.pages++;await this.refresh();
 }
 scheduleRefresh(){clearTimeout(this.timer);this.timer=setTimeout(()=>this.refresh(),200);}
 dispose(){clearTimeout(this.timer);this.active=false;this.generation++;this.request++;}
}
