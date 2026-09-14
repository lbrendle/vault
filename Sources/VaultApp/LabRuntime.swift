import Foundation
#if os(iOS)
import UIKit
#endif

/// A single embedded interpreter, serialized independently of document I/O.
final class LabRuntime {
    static let shared=LabRuntime()
    private let queue=DispatchQueue(label:"vault.lab.python",qos:.userInitiated)
    private let lock=NSLock()
    private var running=false
    private var initialized=false
    static var enabled:Bool { UserDefaults.standard.bool(forKey:"labEnabled") }
    var isRunning:Bool {
        #if os(iOS)
        lock.lock();defer{lock.unlock()};return running
        #else
        return LabHostRuntime.shared.isRunning
        #endif
    }
    func call(_ method:String,args:[String:Any],root:URL,reply:@escaping(Any?,String?)->Void) {
        #if os(iOS)
        if method=="labCancel" {LabPython.cancel();LabModel.cancel();reply(true,nil);return}
        lock.lock()
        if running {lock.unlock();reply(nil,"An experiment is running. Stop it or wait for it to finish.");return}
        running=true;lock.unlock()
        queue.async {
            do {
                if !self.initialized {
                    LabPython.setModelCallback { input in strdup(LabModel.dispatch(String(cString:input))) }
                    LabPython.setGPUCallback { input in
                        let result=LabGPU.dispatch(String(cString:input))
                        return strdup(result)
                    }
                    var error:NSString?
                    guard LabPython.initialize(at:Bundle.main.resourcePath!,error:&error) != nil else {
                        throw NSError(domain:"VaultLab",code:1,userInfo:[NSLocalizedDescriptionKey:error as String? ?? "Python is unavailable"])
                    }
                    self.initialized=true
                }
                let payload:[String:Any]=["method":method,"args":args,"root":root.path,"platform":"ios","deviceLabel":UIDevice.current.userInterfaceIdiom == .pad ? "This iPad":"This iPhone"]
                let data=try JSONSerialization.data(withJSONObject:payload)
                let result=LabPython.dispatch(String(decoding:data,as:UTF8.self))
                let value=try JSONSerialization.jsonObject(with:Data(result.utf8))
                if let failure=(value as? [String:Any])?["error"] as? String {throw NSError(domain:"VaultLab",code:2,userInfo:[NSLocalizedDescriptionKey:failure])}
                self.lock.lock();self.running=false;self.lock.unlock()
                DispatchQueue.main.async{reply(value,nil)}
            }catch{self.lock.lock();self.running=false;self.lock.unlock();DispatchQueue.main.async{reply(nil,error.localizedDescription)}}
        }
        #else
        LabHostRuntime.shared.call(method,args:args,root:root,reply:reply)
        #endif
    }
}
