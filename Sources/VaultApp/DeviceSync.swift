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
    private var listener:NWListener?,browser:NWBrowser?,timer:DispatchSourceTimer?
    private var channels=[PeerChannel](),endpoints=[String:NWEndpoint](),busy=Set<String>()
    private var config:[String:String]?,phase="Not paired",lastSync:Double=0,problem=""
    private let device:String,keyAccount:String
    private var transfer:PeerTransfer?
    private var lastProgress:Double=0,metadataBusy=Set<String>()
    private var forceNextSync=false
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

    }
    func start(){queue.async{[weak self] in self?.startOnQueue()}}
    func stop(){queue.async{[weak self] in self?.stopOnQueue()}}
    private func stopOnQueue(){listener?.cancel();browser?.cancel();timer?.cancel();listener=nil;browser=nil;timer=nil;channels.forEach{$0.close()};modelChannel?.close();modelChannel=nil;channels=[];endpoints=[:];busy=[]}
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
                guard let self else{return};var found=[String:NWEndpoint]()
                for result in results {if case let .service(name,_,_,_)=result.endpoint,let id=PeerIdentity.device(in:name,group:group,excluding:self.device) {found[id]=result.endpoint}}
                self.endpoints=found;self.publish();self.synchronizeAll()
            }
            browser.stateUpdateHandler={[weak self] state in switch state {case .failed(let error),.waiting(let error):self?.problem="Local network: "+error.localizedDescription;self?.publish();default:break}}
            self.browser=browser;browser.start(queue:queue)
            let timer=DispatchSource.makeTimerSource(queue:queue);timer.schedule(deadline:.now()+3,repeating:15);timer.setEventHandler{[weak self] in self?.synchronizeAll()};timer.resume();self.timer=timer
            phase="Waiting for paired devices";problem="";publish()
        }catch{problem=error.localizedDescription;publish()}
    }
    private func serve(_ channel:PeerChannel)async {
        defer{channel.close()}
        do {while !Task.isCancelled {
            let request=try await channel.receive(),command=request["command"] as? String ?? "",args=request["args"] as? [String:Any] ?? [:]
            if command=="hello" {
                #if os(macOS)
                try await channel.send(["version":1,"device":device,"capabilities":PeerTransfer.capabilities,"model":true,"models":ModelLibrary.catalog()["models"] ?? [],"name":Host.current().localizedName ?? "Mac"])
                #else
                try await channel.send(["version":1,"device":device,"capabilities":PeerTransfer.capabilities,"model":false,"name":"iPad or iPhone"])
                #endif
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
                    let c=PeerChannel(NWConnection(to:endpoint,using:PeerTLS.parameters(secret:secret)))
                    do {try await c.ready();let hello=try await c.request("hello");if hello["model"] as? Bool==true {channel=c;remoteModels=hello["models"] ?? [];break}}catch{};c.close()
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
    func documentsChanged(_ paths:[String]){queue.async{[weak self] in guard let self,let transfer=self.transfer else{return};self.changesQueue.async{do{try transfer.catalog.refresh(paths);self.queue.async{self.synchronizeAll()}}catch{self.queue.async{self.problem=error.localizedDescription;self.publish()}}}}}
    private func synchronizeAll(){
        guard let encoded=config?["secret"],let secret=Data(base64Encoded:encoded),let transfer else{return}
        for (id,endpoint) in endpoints where device<id && busy.contains(id) && !metadataBusy.contains(id) {
            metadataBusy.insert(id)
            Task {let c=PeerChannel(NWConnection(to:endpoint,using:PeerTLS.parameters(secret:secret)));defer{c.close();self.queue.async{self.metadataBusy.remove(id)}};do{try await c.ready();try await transfer.synchronizeState(c)}catch{}}
        }
        let force=forceNextSync
        for (id,endpoint) in endpoints where device<id && !busy.contains(id) {
            forceNextSync=false
            busy.insert(id);let channel=PeerChannel(NWConnection(to:endpoint,using:PeerTLS.parameters(secret:secret)));channels.append(channel)
            Task {do {try await channel.ready();try await transfer.synchronize(channel,forceScan:force);self.queue.async{self.lastSync=Date().timeIntervalSince1970;self.problem=""}}catch {self.queue.async{self.problem=error.localizedDescription;self.phase="Will retry when connected"}}
                channel.close();self.queue.async{self.busy.remove(id);self.channels.removeAll{$0===channel};self.publish()}
            }
        }
    }
    private func requestPeerSync(){
        guard let encoded=config?["secret"],let secret=Data(base64Encoded:encoded)else{return}
        for (id,endpoint) in endpoints where device>id {
            Task {let c=PeerChannel(NWConnection(to:endpoint,using:PeerTLS.parameters(secret:secret)));defer{c.close()};do{try await c.ready();_ = try await c.request("requestSync")}catch{self.queue.async{self.problem=error.localizedDescription;self.publish()}}}
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
            case "syncNow":self.forceNextSync=true;self.phase=self.busy.isEmpty ? "Connecting to paired devices":"Sync in progress";self.synchronizeAll();self.requestPeerSync();result=self.status();self.publish()
            default:result=self.status()
            }
            DispatchQueue.main.async{reply(result,nil)}
        }catch{DispatchQueue.main.async{reply(nil,error.localizedDescription)}}
    }}
    private func pairingCode()->String {guard let c=config else{return ""};return "AV1."+(c["group"] ?? "")+"."+(c["secret"] ?? "")}
    private func status()->[String:Any]{["paired":config != nil,"phase":phase,"peers":endpoints.keys.sorted().map{["id":$0,"name":"Paired device · "+$0.prefix(6),"syncing":busy.contains($0)]},"lastSync":lastSync,"error":problem,"device":device,"transport":"TLS 1.2 · ECDHE + ChaCha20-Poly1305"]}
    private func publish(){emit(status())}
    private static func keyQuery(_ account:String)->[String:Any]{[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:(Bundle.main.bundleIdentifier ?? "com.archii.vault")+".device-sync",kSecAttrAccount as String:account]}
    private static func loadKey(_ account:String)->Data? {var q=keyQuery(account);q[kSecReturnData as String]=true;var out:CFTypeRef?;guard SecItemCopyMatching(q as CFDictionary,&out)==errSecSuccess else{return nil};return out as? Data}
    private static func deleteKey(_ account:String){SecItemDelete(keyQuery(account) as CFDictionary)}
    private func saveConfig()throws {let data=try JSONEncoder().encode(config!);let q=Self.keyQuery(keyAccount);let status=SecItemUpdate(q as CFDictionary,[kSecValueData as String:data] as CFDictionary);if status==errSecItemNotFound {var add=q;add[kSecValueData as String]=data;add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else{throw VaultError.message("Could not store the pairing key in Keychain")}}else if status != errSecSuccess {throw VaultError.message("Could not update the pairing key")}}
}
