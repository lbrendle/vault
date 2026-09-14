#if os(macOS)
import Foundation

/// An explicitly enabled, persistent local Python process for the optional Mac host.
final class LabHostRuntime {
    static let shared=LabHostRuntime()
    private let queue=DispatchQueue(label:"vault.lab.host",qos:.userInitiated)
    private let lock=NSLock()
    private var buffered=Data()
    private var process:Process?,input:FileHandle?,output:FileHandle?,running=false
    var isRunning:Bool { lock.lock();defer{lock.unlock()};return running }
    static var enabled:Bool{UserDefaults.standard.bool(forKey:"labHostEnabled")}
    static var executable:String{UserDefaults.standard.string(forKey:"labPythonPath") ?? "/opt/homebrew/bin/python3.12"}
    func status()->[String:Any]{["enabled":Self.enabled,"executable":Self.executable,"available":FileManager.default.isExecutableFile(atPath:Self.executable),"name":Host.current().localizedName ?? "Mac"]}
    func call(_ method:String,args:[String:Any],root:URL,reply:@escaping(Any?,String?)->Void){
        if method=="labHostStatus"{reply(status(),nil);return}
        if method=="labHostConfigure" {
            if let path=args["executable"] as? String {
                guard path.hasPrefix("/"),FileManager.default.isExecutableFile(atPath:path) else{reply(nil,"Choose the absolute path of an installed Python executable.");return}
                UserDefaults.standard.set(path,forKey:"labPythonPath")
            }
            UserDefaults.standard.set(args["enabled"] as? Bool ?? false,forKey:"labHostEnabled")
            cancel();reply(status(),nil);return
        }
        if method=="labCancel"{cancel();reply(true,nil);return}
        lock.lock();if running{lock.unlock();reply(nil,"The Mac lab is already running a command.");return};running=true;lock.unlock()
        queue.async {
            var value:Any?,failure:String?
            do {
                try self.start()
                let request:[String:Any]=["method":method,"args":args,"root":root.path,"platform":"mac"]
                let data=try JSONSerialization.data(withJSONObject:request)
                self.lock.lock();let input=self.input,output=self.output;self.lock.unlock()
                guard let input,let output else{throw NSError(domain:"LabHost",code:3,userInfo:[NSLocalizedDescriptionKey:"The Mac kernel was stopped."])}
                try input.write(contentsOf:data+Data([10]))
                while true {
                    let line=try self.readLine(output)
                    let replyPrefix=Data("VAULT_LAB_REPLY ".utf8),gpuPrefix=Data("VAULT_LAB_GPU ".utf8),modelPrefix=Data("VAULT_LAB_MODEL ".utf8)
                    if line.starts(with:replyPrefix){value=try JSONSerialization.jsonObject(with:line.dropFirst(replyPrefix.count));break}
                    if line.starts(with:modelPrefix){
                        let result=LabModel.dispatch(String(decoding:line.dropFirst(modelPrefix.count),as:UTF8.self))
                        try input.write(contentsOf:Data((result+"\n").utf8))
                    }
                    if line.starts(with:gpuPrefix){
                        let result=LabGPU.dispatch(String(decoding:line.dropFirst(gpuPrefix.count),as:UTF8.self))
                        try input.write(contentsOf:Data((result+"\n").utf8))
                    }
                }
                if let error=(value as? [String:Any])?["error"] as? String{failure=error}
            }catch{failure=error.localizedDescription;self.cancel()}
            self.lock.lock();self.running=false;self.lock.unlock()
            DispatchQueue.main.async{reply(value,failure)}
        }
    }
    private func readLine(_ handle:FileHandle)throws->Data {
        while true {
            if let newline=buffered.firstIndex(of:10){let line=Data(buffered[..<newline]);buffered.removeSubrange(...newline);return line}
            let chunk=handle.availableData
            guard !chunk.isEmpty else{throw NSError(domain:"LabHost",code:1,userInfo:[NSLocalizedDescriptionKey:"The Python process stopped. Run again to start a fresh session."])}
            buffered.append(chunk)
            guard buffered.count<=64*1024*1024 else{throw NSError(domain:"LabHost",code:2,userInfo:[NSLocalizedDescriptionKey:"The Python response exceeded 64 MiB."])}
        }
    }
    private func start()throws {
        lock.lock();defer{lock.unlock()}
        if process?.isRunning==true{return}
        let p=Process(),stdin=Pipe(),stdout=Pipe()
        p.executableURL=URL(fileURLWithPath:Self.executable)
        let resources=Bundle.main.resourceURL!.appendingPathComponent("lab-python")
        // The signed application resources must remain unchanged after imports.
        p.arguments=["-B","-u",resources.appendingPathComponent("vault_host.py").path]
        var env=ProcessInfo.processInfo.environment.filter{!$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("XCTest") && !$0.key.hasPrefix("__XCODE") && $0.key != "XCInjectBundleInto"};env["PYTHONUTF8"]="1";env["PYTHONUNBUFFERED"]="1";p.environment=env
        p.standardInput=stdin;p.standardOutput=stdout;p.standardError=FileHandle.nullDevice
        try p.run();buffered.removeAll();process=p;input=stdin.fileHandleForWriting;output=stdout.fileHandleForReading
    }
    private func cancel(){LabModel.cancel();lock.lock();let p=process,i=input,o=output;process=nil;input=nil;output=nil;lock.unlock();if p?.isRunning==true{p?.terminate()};try? i?.close();try? o?.close()}
}
#endif
