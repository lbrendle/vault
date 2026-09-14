import Foundation
import Network
import Security
import VaultCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// No hosted rendezvous service: peers discover one another using local Bonjour.
final class DeviceSync: @unchecked Sendable {
    private let store:VaultStore
    private let queue=DispatchQueue(label:"vault.discovery",qos:.utility)
    private let changesQueue=DispatchQueue(label:"vault.sync.changes",qos:.utility)
    private let emit:([String:Any])->Void
    private let changed:([String])->Void
    private var modelChannel:PeerChannel?
    private var labChannel:PeerChannel?
    private var labJob:String?
    private var listener:NWListener?,browser:NWBrowser?,timer:DispatchSourceTimer?
    private var channels=[PeerChannel](),endpoints=[String:[NWEndpoint]](),busy=Set<String>()
    private var config:[String:String]?,phase="Not paired",lastSync:Double=0,problem=""
    private let device:String,keyAccount:String
    private var transfer:PeerTransfer?
    private var lastProgress:Double=0,metadataBusy=Set<String>()
    private var forceNextSync=false
    private var generation=UUID(),foregroundObserver:NSObjectProtocol?
    private var connectionStage="Idle"
    init(store:VaultStore,emit:@escaping([String:Any])->Void,changed:@escaping([String])->Void) {
        self.store=store;self.emit=emit;self.changed=changed
        let key="syncDeviceID";if let id=UserDefaults.standard.string(forKey:key){device=id}else{device=UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased();UserDefaults.standard.set(device,forKey:key)}
        keyAccount=VaultStore.fingerprint(Data(Bridge.vaultIdentity(store.root).utf8))
        if let data=Self.loadKey(keyAccount),let value=try? JSONDecoder().decode([String:String].self,from:data){config=value}
        #if DEBUG
        // Isolated integration fixture only; never compiled into release builds.
        if store.root.lastPathComponent=="Sync Acceptance Vault",let code=ProcessInfo.processInfo.environment["VAULT_SYNC_QA_CODE"] {
            let parts=code.components(separatedBy:".");if parts.count==3,let secret=Data(base64Encoded:parts[2]),secret.count==32 {config=["group":parts[1],"secret":parts[2]]}
        }
        #endif
        #if os(iOS)
        foregroundObserver=NotificationCenter.default.addObserver(forName:UIApplication.willEnterForegroundNotification,object:nil,queue:nil){[weak self] _ in self?.start()}
        #else
        foregroundObserver=NotificationCenter.default.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:nil){[weak self] _ in self?.start()}
        #endif
    }
    deinit {if let foregroundObserver{NotificationCenter.default.removeObserver(foregroundObserver)}}
    func start(){queue.async{[weak self] in self?.startOnQueue()}}
    func stop(){queue.async{[weak self] in self?.stopOnQueue()}}
    private func stopOnQueue(){generation=UUID();metadataBusy=[];listener?.cancel();browser?.cancel();timer?.cancel();listener=nil;browser=nil;timer=nil;channels.forEach{$0.close()};modelChannel?.close();modelChannel=nil;labChannel?.close();labChannel=nil;channels=[];endpoints=[:];busy=[]}
    private func startOnQueue(){
        stopOnQueue();guard let config,let encoded=config["secret"],let secret=Data(base64Encoded:encoded),secret.count==32,let group=config["group"] else{publish();return}
        do {
            if transfer==nil {let value=PeerTransfer(catalog:try SyncCatalog(store:store,device:device));value.onChange=changed;value.onProgress={[weak self] s in self?.queue.async{guard let self else{return};self.phase=s;let now=Date().timeIntervalSince1970;if now-self.lastProgress>0.35||s.hasPrefix("Up to date"){self.lastProgress=now;self.publish()}}};transfer=value}
            let listener=try NWListener(using:PeerTLS.parameters(secret:secret),on:.any)
            listener.service=NWListener.Service(name:String(group.prefix(12))+"-"+device,type:"_archiivault._tcp",domain:"local.")
            listener.serviceRegistrationUpdateHandler={[weak self] _ in self?.publish()}
            listener.newConnectionHandler={[weak self] connection in
                guard let self,self.channels.count<8 else{connection.cancel();return}
                let channel=PeerChannel(connection);self.channels.append(channel)
                Task {do{try await channel.ready();self.queue.async{self.phase="Connected securely";self.publish()};await self.serve(channel)}catch{channel.close()};self.queue.async{self.channels.removeAll{$0===channel}}}
            }
            listener.stateUpdateHandler={[weak self] state in if case .failed(let error)=state {self?.problem=error.localizedDescription;self?.publish()}}
            self.listener=listener;listener.start(queue:queue)
            let discovery=NWParameters.tcp;discovery.includePeerToPeer=true
            let browser=NWBrowser(for:.bonjour(type:"_archiivault._tcp",domain:"local."),using:discovery)
            browser.browseResultsChangedHandler={[weak self] results,_ in
                guard let self else{return};var found=[String:[NWEndpoint]]()
                for result in results {if case let .service(name,_,_,_)=result.endpoint,let id=PeerIdentity.device(in:name,group:group,excluding:self.device) {
                    var routes=[NWEndpoint]()
                    if case let .service(name,type,domain,_)=result.endpoint {
                        // Prefer infrastructure Wi-Fi; include the system-selected route.
                        let interfaces=result.interfaces.sorted{a,b in (a.name=="en0" ? 0:1)<(b.name=="en0" ? 0:1)}
                        for interface in interfaces.prefix(3){routes.append(.service(name:name,type:type,domain:domain,interface:interface))}
                    }
                    routes.append(result.endpoint);found[id]=routes}}
                self.endpoints=found;self.publish();self.synchronizeAll()
            }
            browser.stateUpdateHandler={[weak self] state in switch state {case .failed(let error),.waiting(let error):self?.problem="Local network: "+error.localizedDescription;self?.publish();default:break}}
            self.browser=browser;browser.start(queue:queue)
            let timer=DispatchSource.makeTimerSource(queue:queue);timer.schedule(deadline:.now()+3,repeating:15);timer.setEventHandler{[weak self] in self?.synchronizeAll();self?.publish()};timer.resume();self.timer=timer
            phase="Waiting for paired devices";problem="";publish()
        }catch{problem=error.localizedDescription;publish()}
    }
    private func serve(_ channel:PeerChannel)async {
        defer{channel.close()}
        do {while !Task.isCancelled {
            let request=try await channel.receive(),command=request["command"] as? String ?? "",args=request["args"] as? [String:Any] ?? [:]
            if command=="hello" {
                #if os(macOS)
                try await channel.send(["version":1,"device":device,"capabilities":PeerTransfer.capabilities,"model":true,"lab":LabRuntime.enabled && LabHostRuntime.enabled,"models":ModelLibrary.catalog()["models"] ?? [],"name":Host.current().localizedName ?? "Mac"])
                #else
                try await channel.send(["version":1,"device":device,"capabilities":PeerTransfer.capabilities,"model":false,"name":"iPad or iPhone"])
                #endif
            } else if command=="labStatus" {
                #if os(macOS)
                var status=LabHostRuntime.shared.status();status["enabled"]=LabRuntime.enabled && LabHostRuntime.enabled;try await channel.send(status)
                #else
                try await channel.send(["enabled":false])
                #endif
            } else if command=="labRun" {
                #if os(macOS)
                try await serveLab(channel,args:args)
                #else
                try await channel.send(["error":"Choose a paired Mac to host this run."])
                #endif
                return
            } else if command=="labCancel" {
                #if os(macOS)
                let canCancel=await withCheckedContinuation{c in queue.async{c.resume(returning:self.labJob==args["job"] as? String && self.labJob != nil)}}
                if canCancel {LabHostRuntime.shared.call("labCancel",args:[:],root:store.root,reply:{_,_ in})}
                #endif
                try await channel.send(["ok":true]);return
            } else if command=="requestSync" {
                try await channel.send(["ok":true]);queue.async{self.forceNextSync=true;self.synchronizeAll()}
            } else if command=="modelChat" {
                #if os(macOS)
                try await PairedModel.serve(channel:channel,args:args)
                #else
                try await channel.send(["error":"Choose a paired Mac for remote inference"])
                #endif
                return
            }else {
                do {let response=try transfer!.respond(command:command,args:args);try await channel.send(response);if command=="syncComplete"{queue.async{self.lastSync=Date().timeIntervalSince1970;self.phase="Up to date";self.problem="";self.publish()}}}catch{try await channel.send(["error":error.localizedDescription])}
            }
        }}catch{}
    }
    func model(_ method:String,args:[String:Any],event:@escaping([String:Any])->Void,reply:@escaping(Any?,String?)->Void){queue.async{
        if method=="modelStop" {self.modelChannel?.close();self.modelChannel=nil;DispatchQueue.main.async{reply(true,nil)};return}
        guard self.modelChannel==nil else{DispatchQueue.main.async{reply(nil,"A paired model is already answering")};return}
        guard let encoded=self.config?["secret"],let secret=Data(base64Encoded:encoded),!self.endpoints.isEmpty else{DispatchQueue.main.async{reply(nil,"Open Vault on your paired Mac, on the same network. Pair devices in Settings → Device sync.")};return}
        let endpoints=Array(self.endpoints.values)
        Task {
            var channel:PeerChannel?,replied=false,remoteModels:Any=[]
            do {
                for endpoint in endpoints {
                    var candidate:PeerChannel?
                    do {let c=try await PeerChannel.connect(to:endpoint,secret:secret);candidate=c;let hello=try await c.request("hello");if hello["model"] as? Bool==true {channel=c;remoteModels=hello["models"] ?? [];break}}catch{}
                    candidate?.close()
                }
                guard let c=channel else{throw VaultError.message("No paired Mac is available for inference")}
                if method=="modelStatus" {c.close();DispatchQueue.main.async{reply(["installed":true,"remote":true,"models":remoteModels],nil)};return}
                self.queue.async{self.modelChannel=c}
                var forwarded=args
                if let id=args["model_id"] as? String {if id.hasPrefix("remote/"){forwarded["model_id"]=String(id.dropFirst(7))}else if id=="paired-mac"{forwarded.removeValue(forKey:"model_id")}}
                try await c.send(["command":"modelChat","args":forwarded]);replied=true;DispatchQueue.main.async{reply(["started":true,"remote":true],nil)}
                while true {let message=try await c.receive();if let e=message["error"] as? String{throw VaultError.message(e)};if let model=message["model"] as? [String:Any] {event(model);if model["event"] as? String=="unloaded"{break}}}
                c.close()
            }catch {channel?.close();event(["event":"error","data":["message":error.localizedDescription]]);event(["event":"unloaded","data":[:]]);if !replied {DispatchQueue.main.async{reply(nil,error.localizedDescription)}}}
            self.queue.async{self.modelChannel=nil}
        }
    }}
    #if os(macOS)
    private func serveLab(_ channel:PeerChannel,args:[String:Any])async throws {
        guard LabRuntime.enabled && LabHostRuntime.enabled else{try await channel.send(["error":"Enable Lab and the Mac host in Vault on your Mac first."]);return}
        let job=args["job"] as? String ?? ""
        guard UUID(uuidString:job) != nil,let project=args["project"] as? String,!project.isEmpty else{throw VaultError.message("Invalid lab project")}
        let base:String
        if project.hasPrefix("@/"){base=String(project.dropFirst(2));_ = try store.safeURL(base,requireDocument:false)}
        else{guard !project.contains("/"),!project.hasPrefix(".") else{throw VaultError.message("Invalid lab project")};base="Labs/"+project}
        let admitted=await withCheckedContinuation{c in queue.async{if self.labJob != nil{c.resume(returning:false)}else{self.labJob=job;c.resume(returning:true)}}}
        guard admitted else{try await channel.send(["error":"Another lab command is running on the Mac."]);return}
        defer{queue.async{self.labJob=nil}}
        do {
            // Source text is sent with the run. Every supporting file must already match the synced iPad project.
            for file in args["manifest"] as? [[String:Any]] ?? [] {
                guard let path=file["path"] as? String,let hash=file["sha256"] as? String else{throw VaultError.message("Invalid project manifest")}
                let local=try store.safeURL(base.isEmpty ? path:base+"/"+path)
                guard let localHash=try? SyncCatalog.digest(local),localHash==hash else{throw VaultError.message("Sync this project first. The Mac copy differs: "+path)}
            }
            var forwarded=args;forwarded["execution"]="paired-mac"
            let value:Any=try await withCheckedThrowingContinuation{c in LabHostRuntime.shared.call("labRun",args:forwarded,root:store.root){value,error in if let error{c.resume(throwing:VaultError.message(error))}else{c.resume(returning:value ?? [:])}}}
            var result=value as? [String:Any] ?? [:];result["execution"]="paired-mac";result["host"]=Host.current().localizedName ?? "Mac"
            let data=try JSONSerialization.data(withJSONObject:result,options:.withoutEscapingSlashes)
            guard data.count<=64*1024*1024 else{throw VaultError.message("The Mac result exceeds 64 MiB.")}
            let chunkSize=768*1024,count=(data.count+chunkSize-1)/chunkSize
            try await channel.send(["chunks":count])
            for start in stride(from:0,to:data.count,by:chunkSize){try await channel.send(["data":data[start..<min(start+chunkSize,data.count)].base64EncodedString()])}
            documentsChanged((result["files"] as? [[String:Any]] ?? []).compactMap{($0["path"] as? String).map{base.isEmpty ? $0:base+"/"+$0}})
        }catch{try await channel.send(["error":error.localizedDescription])}
    }
    #endif
    func lab(_ method:String,args:[String:Any],reply:@escaping(Any?,String?)->Void){queue.async{
        if method=="labRemoteRun",self.labChannel != nil {DispatchQueue.main.async{reply(nil,"The paired Mac is already running a lab command.")};return}
        guard let encoded=self.config?["secret"],let secret=Data(base64Encoded:encoded) else{DispatchQueue.main.async{reply(nil,"Pair Vault Lab with your Mac in Device sync, and keep both apps open on the same local network.")};return}
        var endpoints=Array(self.endpoints.values)
        if let address=args["address"] as? String,!address.isEmpty {
            do{endpoints=[try Self.directRoute(address)]}catch{DispatchQueue.main.async{reply(nil,error.localizedDescription)};return}
        }
        Task {
            var channel:PeerChannel?
            do {
                for endpoint in endpoints {
                    var candidate:PeerChannel?
                    do {let c=try await PeerChannel.connect(to:endpoint,secret:secret);candidate=c;let hello=try await c.request("hello");if hello["model"] as? Bool==true{channel=c;break}}catch{}
                    candidate?.close()
                }
                guard let c=channel else{throw VaultError.message("No paired Mac is available on this network.")}
                defer{c.close()}
                if method=="labRemoteStatus" {let result=try await c.request("labStatus");DispatchQueue.main.async{reply(result,nil)};return}
                if method=="labRemoteCancel" {_ = try await c.request("labCancel",["job":args["job"] ?? ""]);DispatchQueue.main.async{reply(true,nil)};return}
                self.queue.async{self.labChannel=c}
                defer{self.queue.async{self.labChannel=nil}}
                let first=try await c.request("labRun",args,timeout:660)
                guard let count=first["chunks"] as? Int,count>0,count<=86 else{throw VaultError.message("Invalid lab result from Mac.")}
                var data=Data()
                for _ in 0..<count {let part=try await c.receive();guard let text=part["data"] as? String,let bytes=Data(base64Encoded:text),bytes.count<=768*1024 else{throw VaultError.message("Invalid lab result chunk.")};data.append(bytes)}
                let value=try JSONSerialization.jsonObject(with:data)
                DispatchQueue.main.async{reply(value,nil)}
            }catch{channel?.close();DispatchQueue.main.async{reply(nil,error.localizedDescription)}}
        }
    }}
    func documentsChanged(_ paths:[String]){queue.async{[weak self] in guard let self,let transfer=self.transfer else{return};self.changesQueue.async{do{try transfer.catalog.refresh(paths);self.queue.async{self.synchronizeAll()}}catch{self.queue.async{self.problem=error.localizedDescription;self.publish()}}}}}
    private func synchronizeAll(){
        guard let encoded=config?["secret"],let secret=Data(base64Encoded:encoded),let transfer else{return}
        let run=generation
        for (id,routes) in endpoints where device<id && busy.contains(id) && !metadataBusy.contains(id) {
            metadataBusy.insert(id)
            Task {
                defer{self.queue.async{if self.generation==run{self.metadataBusy.remove(id)}}}
                do {let c=try await PeerChannel.connect(to:routes,secret:secret);defer{c.close()};try await transfer.synchronizeState(c)}catch{}
            }
        }
        let force=forceNextSync
        for (id,routes) in endpoints where device<id && !busy.contains(id) {
            forceNextSync=false;busy.insert(id);connectionStage="Connecting";publish()
            Task {
                do {
                    let channel=try await PeerChannel.connect(to:routes,secret:secret)
                    defer{channel.close();self.queue.async{self.channels.removeAll{$0===channel}}}
                    let current=await withCheckedContinuation{continuation in self.queue.async{
                        if self.generation==run {self.channels.append(channel);self.connectionStage="Connected securely";self.problem="";self.publish();continuation.resume(returning:true)}else{continuation.resume(returning:false)}
                    }}
                    guard current else{return}
                    try await transfer.synchronize(channel,forceScan:force)
                    self.queue.async{if self.generation==run{self.lastSync=Date().timeIntervalSince1970;self.problem=""}}
                }catch {self.queue.async{if self.generation==run{self.problem=error.localizedDescription;self.phase="Will retry when connected"}}}
                self.queue.async{if self.generation==run{self.busy.remove(id);self.publish()}}
            }
        }
    }
    private func requestPeerSync(){
        guard let encoded=config?["secret"],let secret=Data(base64Encoded:encoded)else{return}
        for (id,routes) in endpoints where device>id {
            Task {do{let c=try await PeerChannel.connect(to:routes,secret:secret);defer{c.close()};_ = try await c.request("requestSync")}catch{self.queue.async{self.problem=error.localizedDescription;self.publish()}}}
        }
    }
    func call(_ method:String,args:[String:Any],reply:@escaping(Any?,String?)->Void){queue.async{
        do {
            var result:[String:Any]
            switch method {
            case "syncCreate":
                var bytes=[UInt8](repeating:0,count:32);guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else{throw VaultError.message("Could not create a pairing key")}
                self.config=["group":UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),"secret":Data(bytes).base64EncodedString()];try self.saveConfig();self.startOnQueue();result=self.status();result["code"]=self.pairingCode()
            case "syncJoin":
                let code=(args["code"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines),parts=code.components(separatedBy:".")
                guard parts.count==3,parts[0]=="AV1",parts[1].count==32,parts[1].allSatisfy({$0.isHexDigit}),let key=Data(base64Encoded:parts[2]),key.count==32 else{throw VaultError.message("That pairing code is incomplete. Copy the entire code from your other device.")}
                self.config=["group":parts[1],"secret":parts[2]];try self.saveConfig();self.startOnQueue();result=self.status()
            case "syncCode":result=["code":self.pairingCode()]
            case "syncDisconnect":self.stopOnQueue();self.config=nil;Self.deleteKey(self.keyAccount);self.phase="Not paired";self.problem="";self.lastSync=0;result=self.status();self.publish()
            case "syncNow":if self.busy.isEmpty && (!self.problem.isEmpty || self.endpoints.isEmpty){self.startOnQueue()};self.forceNextSync=true;self.phase=self.busy.isEmpty ? "Connecting to paired devices":"Sync in progress";self.synchronizeAll();self.requestPeerSync();result=self.status();self.publish()
            default:result=self.status()
            }
            DispatchQueue.main.async{reply(result,nil)}
        }catch{DispatchQueue.main.async{reply(nil,error.localizedDescription)}}
    }}
    private func pairingCode()->String {guard let c=config else{return ""};return "AV1."+(c["group"] ?? "")+"."+(c["secret"] ?? "")}
    func labAddress()->String? {
        #if os(macOS)
        return queue.sync {
            guard let port=listener?.port?.rawValue else{return nil}
            var head:UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&head)==0 else{return nil};defer{freeifaddrs(head)}
            var current=head
            while let node=current {
                defer{current=node.pointee.ifa_next}
                guard let address=node.pointee.ifa_addr,address.pointee.sa_family==UInt8(AF_INET) else{continue}
                let value=UnsafeRawPointer(address).assumingMemoryBound(to:sockaddr_in.self).pointee.sin_addr
                var raw=value,buffer=[CChar](repeating:0,count:Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET,&raw,&buffer,socklen_t(INET_ADDRSTRLEN)) != nil else{continue}
                let text=String(cString:buffer)
                if Self.localIPv4(text){return text+":"+String(port)}
            }
            return nil
        }
        #else
        return nil
        #endif
    }
    private static func localIPv4(_ host:String)->Bool {
        let parts=host.split(separator:".").compactMap{Int($0)}
        guard parts.count==4,parts.allSatisfy({$0>=0 && $0<=255}) else{return false}
        return parts[0]==10 || (parts[0]==192 && parts[1]==168) || (parts[0]==172 && (16...31).contains(parts[1])) || (parts[0]==169 && parts[1]==254)
    }
    private static func directRoute(_ address:String)throws->[NWEndpoint] {
        let parts=address.split(separator:":")
        guard parts.count==2,localIPv4(String(parts[0])),let number=UInt16(parts[1]),number>0,let port=NWEndpoint.Port(rawValue:number) else{throw VaultError.message("Use the private IPv4 address and port shown on your Mac, such as 192.168.1.20:50000.")}
        return [.hostPort(host:NWEndpoint.Host(String(parts[0])),port:port)]
    }
    private func status()->[String:Any]{["paired":config != nil,"phase":phase,"peers":endpoints.keys.sorted().map{["id":$0,"name":"Paired device · "+$0.prefix(6),"syncing":busy.contains($0)]},"lastSync":lastSync,"error":problem,"device":device,"transport":"TLS 1.2 · ECDHE + ChaCha20-Poly1305"]}
    private func publish(){
        let value=status();emit(value)
        let diagnostic:[String:Any] = ["updated":Date().timeIntervalSince1970,"paired":config != nil,"peers":endpoints.count,"activeTransfers":busy.count,"connections":channels.map{String(describing:$0.connection.state)},"stage":connectionStage,"lastSync":lastSync,"error":problem,"phase":phase.contains("%") ? (phase.hasPrefix("Sending") ? "Sending document":"Receiving document")+" · "+(phase.components(separatedBy:" · ").last ?? ""):phase]
        let directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Vault/Diagnostics")
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        if let data=try? JSONSerialization.data(withJSONObject:diagnostic,options:.sortedKeys){try? data.write(to:directory.appendingPathComponent("sync.json"),options:.atomic)}
    }
    private static func keyQuery(_ account:String)->[String:Any]{[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:(Bundle.main.bundleIdentifier ?? "com.archii.vault")+".device-sync",kSecAttrAccount as String:account]}
    private static func loadKey(_ account:String)->Data? {var q=keyQuery(account);q[kSecReturnData as String]=true;var out:CFTypeRef?;guard SecItemCopyMatching(q as CFDictionary,&out)==errSecSuccess else{return nil};return out as? Data}
    private static func deleteKey(_ account:String){SecItemDelete(keyQuery(account) as CFDictionary)}
    private func saveConfig()throws {let data=try JSONEncoder().encode(config!);let q=Self.keyQuery(keyAccount);let status=SecItemUpdate(q as CFDictionary,[kSecValueData as String:data] as CFDictionary);if status==errSecItemNotFound {var add=q;add[kSecValueData as String]=data;add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else{throw VaultError.message("Could not store the pairing key in Keychain")}}else if status != errSecSuccess {throw VaultError.message("Could not update the pairing key")}}
}
