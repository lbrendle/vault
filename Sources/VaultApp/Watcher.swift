#if os(macOS)
import Foundation
import CoreServices
final class VaultWatcher {
 private var stream:FSEventStreamRef?
 let changed:([String],Bool)->Void
 init(path:String,changed:@escaping([String],Bool)->Void) {
  self.changed=changed
  var context=FSEventStreamContext(version:0,info:Unmanaged.passUnretained(self).toOpaque(),retain:nil,release:nil,copyDescription:nil)
  let callback:FSEventStreamCallback={_,info,count,paths,flags,_ in
   guard let info else{return};let owner=Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
   let array=unsafeBitCast(paths,to:NSArray.self)
   var names=[String](),rescan=false
   for i in 0..<count {
    if let path=array[i] as? String{names.append(path)}
    if flags[i] & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0 {rescan=true}
   }
   owner.changed(names,rescan)
  }
  stream=FSEventStreamCreate(nil,callback,&context,[path] as CFArray,FSEventStreamEventId(kFSEventStreamEventIdSinceNow),1.5,FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
  if let stream{FSEventStreamSetDispatchQueue(stream,DispatchQueue(label:"vault.events",qos:.utility));FSEventStreamStart(stream)}
 }
 deinit{if let stream{FSEventStreamStop(stream);FSEventStreamInvalidate(stream);FSEventStreamRelease(stream)}}
}
#endif
