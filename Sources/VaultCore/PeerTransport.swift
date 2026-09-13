import Foundation
import Network
import Security

public enum PeerTLS {
    public static func parameters(secret:Data)->NWParameters {
        precondition(secret.count==32)
        let tls=NWProtocolTLS.Options(),identity=Data("ArchiiVault/1".utf8)
        secret.withUnsafeBytes{k in identity.withUnsafeBytes{i in
            sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,DispatchData(bytes:k) as __DispatchData,DispatchData(bytes:i) as __DispatchData)
        }}
        // Apple's external PSK API negotiates TLS 1.2. Restrict negotiation to an
        // authenticated AEAD suite with ephemeral ECDHE and a 256-bit pairing key.
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,tls_ciphersuite_t(rawValue:0xCCAC)!) // ECDHE_PSK_CHACHA20_POLY1305_SHA256
        let tcp=NWProtocolTCP.Options();tcp.noDelay=true
        let p=NWParameters(tls:tls,tcp:tcp);p.includePeerToPeer=true
        return p
    }
}
private final class PeerReadiness: @unchecked Sendable {
    private let lock=NSLock()
    private var continuation:CheckedContinuation<Void,Error>?
    init(_ continuation:CheckedContinuation<Void,Error>){self.continuation=continuation}
    @discardableResult func complete(_ result:Result<Void,Error>)->Bool {
        lock.lock();let pending=continuation;continuation=nil;lock.unlock()
        guard let pending else{return false};pending.resume(with:result);return true
    }
}
private final class PeerDeadline: @unchecked Sendable {
    private let lock=NSLock()
    private var finished=false,expired=false
    func fire(_ cancel:()->Void) {lock.lock();guard !finished else{lock.unlock();return};expired=true;finished=true;lock.unlock();cancel()}
    func finish()->Bool {lock.lock();defer{lock.unlock()};finished=true;return expired}
}
public final class PeerChannel: @unchecked Sendable {
    public let connection:NWConnection
    private let queue=DispatchQueue(label:"vault.peer.transport",qos:.utility)
    public init(_ connection:NWConnection){self.connection=connection}
    public func ready()async throws {
        try await withCheckedThrowingContinuation{(continuation:CheckedContinuation<Void,Error>) in
            let readiness=PeerReadiness(continuation)
            connection.stateUpdateHandler={state in
                switch state {
                case .ready:readiness.complete(.success(()))
                case .failed(let e):readiness.complete(.failure(e))
                case .cancelled:readiness.complete(.failure(VaultError.message("Peer disconnected")))
                default:break
                }
            }
            queue.asyncAfter(deadline:.now()+15){[weak self] in if readiness.complete(.failure(VaultError.message("The paired device could not connect"))) {self?.connection.cancel()}}
            connection.start(queue:queue)
        }
    }
    public func close(){connection.cancel()}
    public func send(_ message:[String:Any])async throws {
        let body=try JSONSerialization.data(withJSONObject:message)
        guard body.count<=2*1024*1024 else{throw VaultError.message("Sync message exceeds frame limit")}
        var count=UInt32(body.count).bigEndian
        var frame=withUnsafeBytes(of:&count){Data($0)};frame.append(body)
        try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in connection.send(content:frame,completion:.contentProcessed{e in if let e{c.resume(throwing:e)}else{c.resume()}})}
    }
    private func read(_ n:Int)async throws->Data {
        try await withCheckedThrowingContinuation{c in
            connection.receive(minimumIncompleteLength:n,maximumLength:n){d,_,end,e in
                if let e{c.resume(throwing:e)}else if let d,d.count==n{c.resume(returning:d)}else{c.resume(throwing:VaultError.message(end ? "Peer disconnected":"Incomplete sync frame"))}
            }
        }
    }
    public func receive()async throws->[String:Any] {
        let header=try await read(4);let n=header.reduce(0){($0<<8)|Int($1)}
        guard n>0,n<=2*1024*1024 else{throw VaultError.message("Invalid sync frame")}
        let body=try await read(n)
        guard let out=try JSONSerialization.jsonObject(with:body) as? [String:Any]else{throw VaultError.message("Invalid sync message")};return out
    }
    public func request(_ command:String,_ args:[String:Any]=[:],timeout:TimeInterval?=nil)async throws->[String:Any] {
        let deadline=PeerDeadline(),wait=timeout ?? (["manifest","journalHead"].contains(command) ? 180:45)
        let timer=DispatchWorkItem{[weak self] in deadline.fire{self?.close()}}
        queue.asyncAfter(deadline:.now()+wait,execute:timer)
        defer{timer.cancel();_ = deadline.finish()}
        do {
            try await send(["command":command,"args":args]);let response=try await receive()
            if let error=response["error"] as? String{throw VaultError.message(error)};return response
        }catch {
            if deadline.finish(){throw VaultError.message("The other device stopped responding. Sync will reconnect and resume.")}
            throw error
        }
    }
}

public final class PeerTransfer: @unchecked Sendable {
    public static let capabilities=["small-file-batches","large-file-blocks-v2","delta-journal-v1"]
    public let catalog:SyncCatalog
    public var onChange:([String])->Void={_ in}
    public var onProgress:(String)->Void={_ in}
    public init(catalog:SyncCatalog){self.catalog=catalog}
    private func json(_ entry:SyncEntry)throws->[String:Any]{try JSONSerialization.jsonObject(with:JSONEncoder().encode(entry)) as! [String:Any]}
    private func entry(_ args:[String:Any])throws->SyncEntry {try JSONDecoder().decode(SyncEntry.self,from:JSONSerialization.data(withJSONObject:args))}
    private func stateURL(_ id:String)throws->URL {
        guard UUID(uuidString:id) != nil else{throw VaultError.message("Invalid state transfer")}
        let dir=catalog.store.metadata.appendingPathComponent("sync/state-transfers");try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        return dir.appendingPathComponent(id+".json")
    }
    private func smallData(_ e:SyncEntry)throws->Data {
        guard catalog.allowed(e),!e.deleted,e.size<=24*1024 else{throw VaultError.message("Invalid small document")}
        let data=try Data(contentsOf:catalog.store.safeURL(e.path))
        guard data.count==e.size,VaultStore.fingerprint(data)==e.hash else{throw VaultError.message("Document changed during transfer")}
        return data
    }
    private func applySmall(_ e:SyncEntry,data:Data)throws {
        guard catalog.allowed(e),!e.deleted,e.size<=24*1024,data.count==e.size,VaultStore.fingerprint(data)==e.hash else{throw VaultError.message("Small document checksum failed")}
        let url=try catalog.staging(e)
        try data.write(to:url,options:.atomic)
        try catalog.apply(e,temporary:url);try? FileManager.default.removeItem(at:url)
    }
    public func respond(command:String,args:[String:Any])throws->[String:Any] {
        switch command {
        case "hello":return ["version":1,"device":catalog.device,"capabilities":Self.capabilities]
        case "journalHead":
            onProgress("Checking changes");if args["force"] as? Bool==true{catalog.invalidate()};try catalog.scan()
            let head=try catalog.journalHead();return ["epoch":head.epoch,"sequence":head.sequence]
        case "journalChanges":
            guard let after=args["after"] as? Int,let through=args["through"] as? Int,args["epoch"] as? String == (try catalog.journalHead()).epoch else{throw VaultError.message("Change journal reset; sync will retry")}
            let page=try catalog.journalChanges(after:after,through:through)
            return ["entries":try page.entries.map(json),"cursor":page.cursor,"more":page.more]
        case "journalCursor":
            return ["sequence":try catalog.peerCursor(args["device"] as? String ?? "",epoch:args["epoch"] as? String ?? "")]
        case "journalAcknowledge":
            guard let sequence=args["sequence"] as? Int else{throw VaultError.message("Invalid change cursor")}
            try catalog.acknowledge(args["device"] as? String ?? "",epoch:args["epoch"] as? String ?? "",sequence:sequence)
            return ["ok":true]
        case "manifest":
            let after=args["after"] as? String ?? "";if after.isEmpty{onProgress("Checking changes");if args["force"] as? Bool==true{catalog.invalidate()};try catalog.scan()}
            let batch=try catalog.manifest(after:after)
            return ["entries":try batch.map(json),"cursor":batch.last?.path ?? "","more":batch.count==128]
        case "offers":
            let batch=args["entries"] as? [[String:Any]] ?? [];guard batch.count<=128 else{throw VaultError.message("Invalid manifest page")}
            let needs=try batch.compactMap{raw->String? in let e=try entry(raw),was=try catalog.entry(e.path);let needed=try catalog.needs(e);if e.deleted,was?.deleted==false,(try catalog.entry(e.path))?.deleted==true{onChange([e.path])};return needed ? e.path:nil};return ["needs":needs]
        case "getSmallBatch":
            guard let requests=args["entries"] as? [[String:Any]],requests.count<=8 else{throw VaultError.message("Invalid small document batch")}
            let files=try requests.map { raw -> [String:Any] in
                let e=try entry(raw)
                guard let current=try catalog.entry(e.path),current.hash==e.hash,!current.deleted else{throw VaultError.message("Document changed before transfer")}
                return ["entry":try json(e),"data":try smallData(e).base64EncodedString()]
            }
            onProgress("Sending \(files.count) documents together")
            return ["files":files]
        case "putSmallBatch":
            guard let files=args["files"] as? [[String:Any]],files.count<=8 else{throw VaultError.message("Invalid small document batch")}
            // Validate the whole frame before applying any of its files.
            let checked=try files.map { raw -> (SyncEntry,Data) in
                guard let value=raw["entry"] as? [String:Any],let data=Data(base64Encoded:raw["data"] as? String ?? "") else{throw VaultError.message("Invalid small document")}
                let e=try entry(value)
                guard catalog.allowed(e),!e.deleted,e.size<=24*1024,data.count==e.size,VaultStore.fingerprint(data)==e.hash else{throw VaultError.message("Small document checksum failed")}
                return (e,data)
            }
            for (e,data) in checked {try applySmall(e,data:data)}
            onChange(checked.map{$0.0.path});onProgress("Received \(checked.count) documents together")
            return ["ok":true]
        case "get":
            let path=args["path"] as? String ?? "",hash=args["hash"] as? String ?? "",offset=args["offset"] as? Int ?? -1
            guard let e=try catalog.entry(path),catalog.allowed(e),!e.deleted,e.hash==hash,offset>=0,offset<=e.size else{throw VaultError.message("Document changed before transfer")}
            let length=min(1024*1024,max(1,args["length"] as? Int ?? 128*1024))
            let f=try FileHandle(forReadingFrom:catalog.store.safeURL(path));defer{try? f.close()};try f.seek(toOffset:UInt64(offset));let d=try f.read(upToCount:length) ?? Data()
            onProgress("Sending \(e.path) · \(min(e.size,offset+d.count)*100/max(1,e.size))%")
            return ["data":d.base64EncodedString(),"offset":offset,"size":e.size]
        case "begin":
            let e=try entry(args);guard catalog.allowed(e),!e.deleted else{throw VaultError.message("Invalid document offer")}
            let url=try catalog.staging(e);if !FileManager.default.fileExists(atPath:url.path){FileManager.default.createFile(atPath:url.path,contents:Data())};let size=(try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
            if size>e.size {let f=try FileHandle(forWritingTo:url);try f.truncate(atOffset:0);try f.close();return ["offset":0]};return ["offset":size]
        case "put":
            guard let raw=args["entry"] as? [String:Any],let data=Data(base64Encoded:args["data"] as? String ?? ""),data.count<=1024*1024 else{throw VaultError.message("Invalid file block")}
            let e=try entry(raw),offset=args["offset"] as? Int ?? -1;let url=try catalog.staging(e)
            guard offset>=0,offset+data.count<=e.size else{throw VaultError.message("Invalid transfer offset")}
            if !FileManager.default.fileExists(atPath:url.path){FileManager.default.createFile(atPath:url.path,contents:Data())}
            let f=try FileHandle(forWritingTo:url);defer{try? f.close()}
            guard try f.seekToEnd()==UInt64(offset)else{throw VaultError.message("Transfer offset changed")};try f.write(contentsOf:data)
            onProgress("Receiving \(e.path) · \((offset+data.count)*100/max(1,e.size))%")
            return ["offset":offset+data.count]
        case "finish":
            let e=try entry(args),url=try catalog.staging(e);try catalog.apply(e,temporary:url);try? FileManager.default.removeItem(at:url);onChange([e.path]);return ["ok":true]
        case "syncComplete":onProgress("Up to date");return ["ok":true]
        case "stateDigest":return ["hash":VaultStore.fingerprint(try JSONSerialization.data(withJSONObject:catalog.store.sharedState(),options:.sortedKeys))]
        case "stateExport":
            let data=try JSONSerialization.data(withJSONObject:catalog.store.sharedState()),id=UUID().uuidString
            guard data.count<=256*1024*1024 else{throw VaultError.message("Conversation state exceeds the 256 MiB transfer limit")}
            try data.write(to:stateURL(id),options:.atomic);return ["id":id,"size":data.count]
        case "stateRead":
            let id=args["id"] as? String ?? "",offset=args["offset"] as? Int ?? -1
            guard offset>=0 else{throw VaultError.message("Invalid state offset")}
            let f=try FileHandle(forReadingFrom:stateURL(id));defer{try? f.close()};try f.seek(toOffset:UInt64(offset));return ["data":(try f.read(upToCount:128*1024) ?? Data()).base64EncodedString()]
        case "stateBegin":
            let id=UUID().uuidString;try Data().write(to:stateURL(id));return ["id":id]
        case "statePut":
            let id=args["id"] as? String ?? "",offset=args["offset"] as? Int ?? -1
            guard offset>=0,let d=Data(base64Encoded:args["data"] as? String ?? ""),d.count<=128*1024,offset+d.count<=256*1024*1024 else{throw VaultError.message("Invalid state block")}
            let f=try FileHandle(forWritingTo:stateURL(id));defer{try? f.close()};guard try f.seekToEnd()==UInt64(offset)else{throw VaultError.message("Invalid state offset")};try f.write(contentsOf:d);return ["ok":true]
        case "stateCommit":
            let url=try stateURL(args["id"] as? String ?? "");defer{try? FileManager.default.removeItem(at:url)}
            let data=try Data(contentsOf:url);guard VaultStore.fingerprint(data)==args["hash"] as? String,let value=try JSONSerialization.jsonObject(with:data) as? [String:Any]else{throw VaultError.message("Conversation transfer checksum failed")}
            try catalog.store.mergeSharedState(value);onChange([]);return ["ok":true]
        case "stateClose":try? FileManager.default.removeItem(at:stateURL(args["id"] as? String ?? ""));return ["ok":true]
        case "state":
            if let state=args["state"] as? [String:Any] {try catalog.store.mergeSharedState(state);onChange([])}
            return ["state":try catalog.store.sharedState()]
        default:throw VaultError.message("Unsupported sync operation")
        }
    }
    public func serve(_ channel:PeerChannel)async {
        defer{channel.close()}
        do {while !Task.isCancelled {let request=try await channel.receive();let response:[String:Any];do{response=try respond(command:request["command"] as? String ?? "",args:request["args"] as? [String:Any] ?? [:])}catch{response=["error":error.localizedDescription]};try await channel.send(response)}}catch{}
    }
    public func synchronize(_ channel:PeerChannel,forceScan:Bool=false)async throws {
        let hello = try await channel.request("hello",["device":catalog.device])
        guard let remoteDevice=hello["device"] as? String,!remoteDevice.isEmpty,remoteDevice != catalog.device else{throw VaultError.message("Ignored a connection to this same device.")}
        let capabilities=hello["capabilities"] as? [String] ?? [],batches=capabilities.contains("small-file-batches"),blockSize=capabilities.contains("large-file-blocks-v2") ? 1024*1024:128*1024
        try await synchronizeState(channel);onProgress("Checking document changes");if forceScan{catalog.invalidate()};try catalog.scan()
        let delta=capabilities.contains("delta-journal-v1")
        var remoteEpoch="",remoteThrough=0,remoteAfter=0
        if delta {
            let head=try await channel.request("journalHead",["force":forceScan])
            guard let epoch=head["epoch"] as? String,UUID(uuidString:epoch) != nil,let sequence=head["sequence"] as? Int,sequence>=0 else{throw VaultError.message("Invalid change journal")}
            remoteEpoch=epoch;remoteThrough=sequence;remoteAfter=try catalog.peerCursor(remoteDevice,epoch:epoch)
            guard remoteAfter<=remoteThrough else{throw VaultError.message("The remote change journal moved backwards")}
        }
        var cursor="",more=true,received=0,sent=0
        while more {
            let response=try await (delta ? channel.request("journalChanges",["epoch":remoteEpoch,"after":remoteAfter,"through":remoteThrough]):channel.request("manifest",["after":cursor,"force":forceScan && cursor.isEmpty]))
            var pending=[SyncEntry]()
            for raw in response["entries"] as? [[String:Any]] ?? [] {
                let e=try entry(raw),was=try catalog.entry(e.path)
                if try catalog.needs(e){pending.append(e)}else if e.deleted,was?.deleted==false{onChange([e.path])}
            }
            if batches {
                let small=pending.filter{!$0.deleted && $0.size<=24*1024}
                for start in stride(from:0,to:small.count,by:8) {
                    let group=Array(small[start..<min(start+8,small.count)])
                    let reply=try await channel.request("getSmallBatch",["entries":try group.map(json)])
                    guard let files=reply["files"] as? [[String:Any]],files.count==group.count else{throw VaultError.message("Incomplete document batch")}
                    for (raw,e) in zip(files,group) {
                        guard let value=raw["entry"] as? [String:Any],try entry(value)==e,let data=Data(base64Encoded:raw["data"] as? String ?? "") else{throw VaultError.message("Unexpected document batch")}
                        try applySmall(e,data:data);received+=1
                    }
                    onChange(group.map{$0.path});onProgress("Received \(received) documents")
                }
                pending.removeAll{!$0.deleted && $0.size<=24*1024}
            }
            for e in pending {
                let url=try catalog.staging(e);if !FileManager.default.fileExists(atPath:url.path){FileManager.default.createFile(atPath:url.path,contents:Data())}
                let f=try FileHandle(forWritingTo:url)
                do {
                    var offset=Int(try f.seekToEnd());if offset>e.size{try f.truncate(atOffset:0);offset=0}
                    while offset<e.size {
                        onProgress("Receiving \(e.path) · \(e.size==0 ? 100:offset*100/e.size)%")
                        let reply=try await channel.request("get",["path":e.path,"hash":e.hash,"offset":offset,"length":blockSize])
                        guard let d=Data(base64Encoded:reply["data"] as? String ?? ""),!d.isEmpty,offset+d.count<=e.size else{throw VaultError.message("Incomplete transfer; will resume")}
                        try f.write(contentsOf:d);offset+=d.count
                    }
                    try f.synchronize();try f.close();try catalog.apply(e,temporary:url);try? FileManager.default.removeItem(at:url);received+=1;onChange([e.path])
                }catch{try? f.close();throw error}
            }
            more=response["more"] as? Bool ?? false;cursor=response["cursor"] as? String ?? ""
            if delta {
                guard let next=response["cursor"] as? Int,next>=remoteAfter,next<=remoteThrough,(!more || next>remoteAfter) else{throw VaultError.message("Invalid change page")}
                // Only advance after every file in this page has been verified/applied.
                try catalog.acknowledge(remoteDevice,epoch:remoteEpoch,sequence:next);remoteAfter=next
            }
            try await synchronizeState(channel)
        }
        cursor=""
        let localHead=try catalog.journalHead()
        var localAfter=0
        if delta {
            let reply=try await channel.request("journalCursor",["device":catalog.device,"epoch":localHead.epoch])
            guard let sequence=reply["sequence"] as? Int,sequence>=0,sequence<=localHead.sequence else{throw VaultError.message("Invalid peer change cursor")};localAfter=sequence
        }
        repeat {
            let batch:[SyncEntry]
            if delta {let page=try catalog.journalChanges(after:localAfter,through:localHead.sequence);batch=page.entries;more=page.more;localAfter=page.cursor}
            else {batch=try catalog.manifest(after:cursor);more=batch.count==128;cursor=batch.last?.path ?? ""}
            let allowed=batch.filter(catalog.allowed)
            let response=try await channel.request("offers",["entries":try allowed.map(json)]),needed=Set(response["needs"] as? [String] ?? [])
            var outgoing=allowed.filter{needed.contains($0.path) && !$0.deleted}
            if batches {
                let small=outgoing.filter{$0.size<=24*1024}
                for start in stride(from:0,to:small.count,by:8) {
                    let group=Array(small[start..<min(start+8,small.count)])
                    let files=try group.map { e -> [String:Any] in ["entry":try json(e),"data":try smallData(e).base64EncodedString()] }
                    _ = try await channel.request("putSmallBatch",["files":files]);sent+=group.count;onProgress("Sent \(sent) documents")
                }
                outgoing.removeAll{$0.size<=24*1024}
            }
            for e in outgoing {
                let raw=try json(e),reply=try await channel.request("begin",raw)
                var offset=reply["offset"] as? Int ?? 0;guard offset>=0,offset<=e.size else{throw VaultError.message("Invalid peer offset")}
                let f=try FileHandle(forReadingFrom:catalog.store.safeURL(e.path));defer{try? f.close()};try f.seek(toOffset:UInt64(offset))
                while offset<e.size {
                    onProgress("Sending \(e.path) · \(offset*100/max(1,e.size))%")
                    guard let d=try f.read(upToCount:blockSize),!d.isEmpty else{throw VaultError.message("Document changed during transfer")}
                    _ = try await channel.request("put",["entry":raw,"offset":offset,"data":d.base64EncodedString()]);offset+=d.count
                }
                _ = try await channel.request("finish",raw);sent+=1
            }
            if delta {_ = try await channel.request("journalAcknowledge",["device":catalog.device,"epoch":localHead.epoch,"sequence":localAfter])}
            try await synchronizeState(channel)
        }while more
        try await synchronizeState(channel)
        _ = try? await channel.request("syncComplete")
        onProgress("Up to date · \(received) received, \(sent) sent")
    }
    public func synchronizeState(_ channel:PeerChannel)async throws {
        let data=try JSONSerialization.data(withJSONObject:catalog.store.sharedState(),options:.sortedKeys)
        let digest=try await channel.request("stateDigest")
        if digest["hash"] as? String==VaultStore.fingerprint(data){return}
        guard data.count<=256*1024*1024 else{throw VaultError.message("Conversation state exceeds the transfer limit")}
        let upload=try await channel.request("stateBegin"),uploadID=upload["id"] as? String ?? ""
        for offset in stride(from:0,to:data.count,by:128*1024) {_ = try await channel.request("statePut",["id":uploadID,"offset":offset,"data":data.subdata(in:offset..<min(offset+128*1024,data.count)).base64EncodedString()])}
        _ = try await channel.request("stateCommit",["id":uploadID,"hash":VaultStore.fingerprint(data)])
        let download=try await channel.request("stateExport"),downloadID=download["id"] as? String ?? "",size=download["size"] as? Int ?? -1
        guard size>=0,size<=256*1024*1024 else{throw VaultError.message("Invalid conversation transfer size")}
        var downloaded=Data()
        while downloaded.count<size {let response=try await channel.request("stateRead",["id":downloadID,"offset":downloaded.count]);guard let block=Data(base64Encoded:response["data"] as? String ?? ""),!block.isEmpty,downloaded.count+block.count<=size else{throw VaultError.message("Incomplete conversation transfer")};downloaded.append(block)}
        if let state=try JSONSerialization.jsonObject(with:downloaded) as? [String:Any]{try catalog.store.mergeSharedState(state);onChange([])}
        _ = try await channel.request("stateClose",["id":downloadID])
    }
}
extension VaultStore {
    func sharedMerge(local:[String:Any],remote:[String:Any])->[String:Any] {
        var local=local,chats=local["chats"] as? [[String:Any]] ?? []
        func encoded(_ object:Any)->Data{(try? JSONSerialization.data(withJSONObject:object,options:.sortedKeys)) ?? Data()}
        func messages(_ chat:[String:Any])->[String]{(chat["messages"] as? [[String:Any]] ?? []).map{($0["role"] as? String ?? "")+":"+($0["content"] as? String ?? "")}}
        for incoming in remote["chats"] as? [[String:Any]] ?? [] {
            guard let id=incoming["id"] as? String else{continue}
            if let i=chats.firstIndex(where:{$0["id"] as? String==id}) {
                let current=chats[i],a=(current["updated"] as? Double) ?? 0,b=(incoming["updated"] as? Double) ?? 0
                let old=messages(current),new=messages(incoming)
                let prefix=zip(old,new).allSatisfy{$0==$1 || $0.hasPrefix($1) || $1.hasPrefix($0)}
                let useIncoming=b>a || b==a && new.count>old.count
                if !prefix {
                    var branch=useIncoming ? current:incoming
                    let branchID=id+"-sync-"+VaultStore.fingerprint(encoded(branch["messages"] ?? [])).prefix(12)
                    branch["id"]=branchID;branch["title"]=(branch["title"] as? String ?? "Conversation")+" · sync copy"
                    if !chats.contains(where:{$0["id"] as? String==branchID}){chats.append(branch)}
                }
                if useIncoming {chats[i]=incoming}
            }else{chats.append(incoming)}
        }
        local["chats"]=chats.sorted{(($0["updated"] as? Double) ?? 0)>(($1["updated"] as? Double) ?? 0)}
        var changes=local["bookmarkChanges"] as? [String:[String:Any]] ?? [:]
        for (path,value) in remote["bookmarkChanges"] as? [String:[String:Any]] ?? [:] {
            let a=changes[path]?["modified"] as? Double ?? -1,b=value["modified"] as? Double ?? 0
            if b>a || b==a && value["present"] as? Bool==false {changes[path]=value}
        }
        let bookmarks=Set((local["bookmarks"] as? [String] ?? [])+(remote["bookmarks"] as? [String] ?? [])).union(changes.keys)
        local["bookmarks"]=bookmarks.filter{changes[$0]?["present"] as? Bool != false}.sorted();local["bookmarkChanges"]=changes
        return local
    }
    public func mergeSharedState(_ remote:[String:Any])throws {try withMutation{try saveState(sharedMerge(local:state(),remote:remote))}}
    public func sharedState()throws->[String:Any]{let s=try state();let chats=(s["chats"] as? [[String:Any]] ?? []).filter{ chat in !(chat["messages"] as? [[String:Any]] ?? []).contains{ $0["status"] as? String == "streaming" } };return ["chats":chats,"bookmarks":s["bookmarks"] ?? [],"bookmarkChanges":s["bookmarkChanges"] ?? [:]]}
}
