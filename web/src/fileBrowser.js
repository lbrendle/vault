// Keep the visible page window stable when sync changes the directory underneath it.
export class FileBrowser {
 constructor(list,onChange,onError){this.list=list;this.onChange=onChange;this.onError=onError;this.generation=0;this.path='';this.pages=1;this.rows=[];this.more=false;this.busy=false;this.active=false;this.timer=null;this.flight=null;this.error=null;}
 publish(){this.onChange({path:this.path,rows:this.rows,more:this.more,busy:this.busy,error:this.error});}
 reset(path,active=true){clearTimeout(this.timer);this.generation++;this.flight=null;this.path=path;this.active=active;this.pages=1;this.rows=[];this.more=false;this.busy=false;this.error=null;this.publish();if(active)return this.refresh();}
 refresh(){
  if(!this.active)return;
  // Sync can arrive faster than a folder can load. Publish each completed
  // result, then fetch changes once; never invalidate it on every sync event.
  if(this.flight){this.flight.again=true;return this.flight.promise;}
  const flight={generation:this.generation,path:this.path,again:false};this.flight=flight;
  flight.promise=this.run(flight);return flight.promise;
 }
 async run(flight){
  this.busy=true;this.error=null;this.publish();
  do{
   flight.again=false;
   try{
    const batches=await Promise.all(Array.from({length:this.pages},(_,page)=>this.list({path:flight.path,offset:page*200})));
    if(flight.generation!==this.generation)return;
    this.rows=batches.flat();this.more=batches.at(-1).filter(row=>!row.directory).length===200;this.error=null;
   }catch(error){if(flight.generation!==this.generation)return;this.error=error?.message||String(error);this.onError(error);}
   this.publish();
  }while(flight.again&&this.active);
  if(flight.generation===this.generation){this.flight=null;this.busy=false;this.publish();}
 }
 async loadMore(){
  if(!this.active||this.busy||!this.more)return;
  this.pages++;await this.refresh();
 }
 scheduleRefresh(){clearTimeout(this.timer);this.timer=setTimeout(()=>this.refresh(),200);}
 dispose(){clearTimeout(this.timer);this.active=false;this.generation++;this.flight=null;}
}
