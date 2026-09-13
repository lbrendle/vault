import Foundation
import CryptoKit

public struct SyncEntry: Codable, Equatable, Sendable {
    public var path:String
    public var hash:String
    public var size:Int
    public var clock:[String:Int]
    public var deleted:Bool
    public init(path:String,hash:String,size:Int,clock:[String:Int],deleted:Bool=false){self.path=path;self.hash=hash;self.size=size;self.clock=clock;self.deleted=deleted}
    public func dominates(_ other:SyncEntry)->Bool {Set(clock.keys).union(other.clock.keys).allSatisfy{clock[$0,default:0]>=other.clock[$0,default:0]}}
    public func merged(_ other:SyncEntry)->[String:Int]{clock.merging(other.clock,uniquingKeysWith:max)}
}

/// A version vector, content hash, and durable tombstone for each document.
/// The disposable text index is never used as evidence that a document was deleted.
public final class SyncCatalog: @unchecked Sendable {
    public let store:VaultStore
    public let device:String
    public let db:Database
    private let lock=NSRecursiveLock()
    private var lastFullScan=Date.distantPast
    public init(store:VaultStore,device:String)throws {
        self.store=store;self.device=device
        db=try Database(store.cache.appendingPathComponent("sync.sqlite"))
        try db.execute("CREATE TABLE IF NOT EXISTS entries(path TEXT PRIMARY KEY,hash TEXT,size INTEGER,modified REAL,clock TEXT,deleted INTEGER,seen TEXT)")
        try db.execute("CREATE INDEX IF NOT EXISTS entries_content ON entries(hash,size) WHERE deleted=0")
        // The latest change per path is enough: version vectors retain causality.
        // Triggers commit the sequence together with the entry, including during scans.
        try db.transaction {
            try db.execute("CREATE TABLE IF NOT EXISTS journal_meta(id INTEGER PRIMARY KEY,epoch TEXT NOT NULL,sequence INTEGER NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS journal_changes(path TEXT PRIMARY KEY,sequence INTEGER NOT NULL)")
            try db.execute("CREATE INDEX IF NOT EXISTS journal_sequence ON journal_changes(sequence)")
            try db.execute("CREATE TABLE IF NOT EXISTS journal_peers(peer TEXT PRIMARY KEY,epoch TEXT NOT NULL,sequence INTEGER NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS journal_policy(id INTEGER PRIMARY KEY,hash TEXT NOT NULL)")
            if try db.execute("SELECT id FROM journal_meta WHERE id=1").isEmpty {
                try db.execute("INSERT INTO journal_changes SELECT path,rowid FROM entries")
                try db.execute("INSERT INTO journal_meta SELECT 1,?,COALESCE(MAX(rowid),0) FROM entries",[UUID().uuidString])
            }
            try db.execute("CREATE TRIGGER IF NOT EXISTS sync_journal_insert AFTER INSERT ON entries BEGIN UPDATE journal_meta SET sequence=sequence+1 WHERE id=1; INSERT INTO journal_changes SELECT new.path,sequence FROM journal_meta WHERE id=1 ON CONFLICT(path) DO UPDATE SET sequence=excluded.sequence; END")
            try db.execute("CREATE TRIGGER IF NOT EXISTS sync_journal_update AFTER UPDATE OF hash,size,clock,deleted ON entries WHEN old.hash<>new.hash OR old.size<>new.size OR old.clock<>new.clock OR old.deleted<>new.deleted BEGIN UPDATE journal_meta SET sequence=sequence+1 WHERE id=1; INSERT INTO journal_changes SELECT new.path,sequence FROM journal_meta WHERE id=1 ON CONFLICT(path) DO UPDATE SET sequence=excluded.sequence; END")
        }
    }
    public static func digest(_ url:URL)throws->String {
        let f=try FileHandle(forReadingFrom:url);defer{try? f.close()};var h=SHA256()
        while let d=try f.read(upToCount:1024*1024),!d.isEmpty {h.update(data:d)}
        return h.finalize().map{String(format:"%02x",$0)}.joined()
    }
    private func decode(_ row:[String:Any])->SyncEntry {
        SyncEntry(path:row["path"] as! String,hash:row["hash"] as! String,size:row["size"] as! Int,clock:(try? JSONDecoder().decode([String:Int].self,from:Data((row["clock"] as! String).utf8))) ?? [:],deleted:(row["deleted"] as! Int)==1)
    }
    public func entry(_ path:String)throws->SyncEntry? {try db.execute("SELECT * FROM entries WHERE path=?",[path]).first.map(decode)}
    private func put(_ e:SyncEntry,modified:Double=0,seen:String="")throws {
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let clocks=String(data:try encoder.encode(e.clock),encoding:.utf8)!
        try db.execute("INSERT INTO entries VALUES(?,?,?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET hash=excluded.hash,size=excluded.size,modified=excluded.modified,clock=excluded.clock,deleted=excluded.deleted,seen=excluded.seen",[e.path,e.hash,e.size,modified,clocks,e.deleted ? 1:0,seen])
    }
    @discardableResult private func observe(_ path:String,seen:String="")throws->SyncEntry? {
        let url=try store.safeURL(path)
        let previous=try entry(path)
        guard FileManager.default.fileExists(atPath:url.path) else {
            if var old=previous,!old.deleted {old.deleted=true;old.hash="";old.size=0;old.clock[device,default:0]+=1;try put(old,seen:seen);return old};return previous
        }
        let v=try url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey,.isRegularFileKey]);guard v.isRegularFile==true else{throw VaultError.message("Sync supports regular document files")}
        let size=v.fileSize ?? 0,mtime=v.contentModificationDate?.timeIntervalSince1970 ?? 0
        let row=try db.execute("SELECT modified,size FROM entries WHERE path=?",[path]).first
        if let previous,!previous.deleted,row?["modified"] as? Double==mtime,row?["size"] as? Int==size {if !seen.isEmpty{try db.execute("UPDATE entries SET seen=? WHERE path=?",[seen,path])};return previous}
        let hash=try Self.digest(url)
        let after=try URL(fileURLWithPath:url.path).resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
        guard after.fileSize==v.fileSize,after.contentModificationDate==v.contentModificationDate else {throw VaultError.message("A file changed while preparing sync. It will retry on the next pass.")}
        var e=previous ?? SyncEntry(path:path,hash:hash,size:size,clock:[:]);if previous==nil||e.hash != hash||e.deleted {e.clock[device,default:0]+=1};e.hash=hash;e.size=size;e.deleted=false;try put(e,modified:mtime,seen:seen);return e
    }
    public func scan()throws {
        lock.lock();defer{lock.unlock()};if Date().timeIntervalSince(lastFullScan)<120{return};let generation=UUID().uuidString
        var failed=false
        let keys:[URLResourceKey]=[.isDirectoryKey,.isSymbolicLinkKey,.isRegularFileKey,.fileSizeKey,.contentModificationDateKey]
        guard let iterator=FileManager.default.enumerator(at:store.root,includingPropertiesForKeys:keys,options:[],errorHandler:{_,_ in failed=true;return true})else{throw VaultError.message("Vault is not available for sync")}
        var batch=[(String,URLResourceValues)]()
        func flush()throws {
            try db.transaction {for (path,values) in batch {
                let previous=try db.execute("SELECT modified,size,deleted FROM entries WHERE path=?",[path]).first
                if values.isRegularFile==true,previous?["deleted"] as? Int==0,
                   previous?["size"] as? Int==values.fileSize,
                   previous?["modified"] as? Double==values.contentModificationDate?.timeIntervalSince1970 {
                    // Enumeration already excludes symlinks and excluded ancestors.
                    // Reuse metadata for unchanged entries without reopening every
                    // path component. Content reads/transfers still use safeURL
                    // and validate the stored checksum before anything is sent.
                    try db.execute("UPDATE entries SET seen=? WHERE path=?",[generation,path])
                }else{try observe(path,seen:generation)}
            }}
            batch.removeAll(keepingCapacity:true)
        }
        for case let url as URL in iterator {
            let path=String(url.path.dropFirst(store.root.path.count+1)),v=try url.resourceValues(forKeys:Set(keys))
            if v.isSymbolicLink==true {iterator.skipDescendants();continue}
            if v.isDirectory==true {if !store.rules.includes(path,directory:true){iterator.skipDescendants()};continue}
            if store.rules.includes(path){batch.append((path,v))}
            if batch.count>=128{try flush()}
        }
        try flush();guard !failed else{throw VaultError.message("Some folders were unavailable. Sync paused to protect your files.")}
        for row in try db.execute("SELECT path FROM entries WHERE seen<>? AND deleted=0",[generation]) {let path=row["path"] as! String;if store.rules.includes(path){try observe(path,seen:generation)}}
        lastFullScan=Date()
    }
    public func invalidate(){lock.lock();lastFullScan = .distantPast;lock.unlock()}
    public func refresh(_ paths:[String])throws {lock.lock();defer{lock.unlock()};for path in paths {if store.rules.includes(path){try observe(path)}else if store.rules.includes(path,directory:true){lastFullScan = .distantPast}}}
    public func manifest(after:String="",limit:Int=128)throws->[SyncEntry] {
        lock.lock();defer{lock.unlock()}
        // Filtering must not truncate pagination when library rules change.
        return try db.execute("SELECT * FROM entries WHERE path>? ORDER BY path LIMIT ?",[after,min(limit,256)]).map(decode)
    }
    public func journalHead()throws->(epoch:String,sequence:Int) {
        try reconcileRules()
        let row=try db.execute("SELECT epoch,sequence FROM journal_meta WHERE id=1")[0]
        return (row["epoch"] as! String,row["sequence"] as! Int)
    }
    private func reconcileRules()throws {
        lock.lock();defer{lock.unlock()}
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let hash=VaultStore.fingerprint(try encoder.encode(store.rules))
        let previous=try db.execute("SELECT hash FROM journal_policy WHERE id=1").first?["hash"] as? String
        guard previous != hash else{return}
        try db.transaction {
            if previous != nil {
                // Newly included paths need a fresh exchange even if their bytes
                // have not changed since a peer last excluded them.
                try db.execute("UPDATE journal_meta SET epoch=? WHERE id=1",[UUID().uuidString])
                try db.execute("DELETE FROM journal_peers")
                lastFullScan = .distantPast
            }
            try db.execute("INSERT INTO journal_policy VALUES(1,?) ON CONFLICT(id) DO UPDATE SET hash=excluded.hash",[hash])
        }
    }
    public func journalChanges(after:Int,through:Int,limit:Int=128)throws->(entries:[SyncEntry],cursor:Int,more:Bool) {
        guard after>=0,through>=after,limit>0 else{throw VaultError.message("Invalid change cursor")}
        let count=min(limit,256)
        let rows=try db.execute("SELECT e.*,j.sequence FROM journal_changes j JOIN entries e ON e.path=j.path WHERE j.sequence>? AND j.sequence<=? ORDER BY j.sequence LIMIT ?",[after,through,count])
        let more=rows.count==count
        return (rows.map(decode),more ? rows.last!["sequence"] as! Int:through,more)
    }
    public func peerCursor(_ peer:String,epoch:String)throws->Int {
        try db.execute("SELECT sequence FROM journal_peers WHERE peer=? AND epoch=?",[peer,epoch]).first?["sequence"] as? Int ?? 0
    }
    public func acknowledge(_ peer:String,epoch:String,sequence:Int)throws {
        guard !peer.isEmpty,peer.count<=128,UUID(uuidString:epoch) != nil,sequence>=0 else{throw VaultError.message("Invalid peer cursor")}
        try db.execute("INSERT INTO journal_peers VALUES(?,?,?) ON CONFLICT(peer) DO UPDATE SET sequence=CASE WHEN journal_peers.epoch=excluded.epoch THEN MAX(journal_peers.sequence,excluded.sequence) ELSE excluded.sequence END,epoch=excluded.epoch",[peer,epoch,sequence])
    }
    public func allowed(_ e:SyncEntry)->Bool {store.rules.includes(e.path) && !e.path.isEmpty && !e.path.split(separator:"/").contains("..") && !e.path.hasPrefix("/") && e.size>=0 && e.size<=128*1024*1024*1024 && e.clock.count<=128 && e.clock.values.allSatisfy{$0>=0} && (e.deleted || e.hash.count==64 && e.hash.allSatisfy{$0.isHexDigit})}
    public func needs(_ remote:SyncEntry)throws->Bool {
        lock.lock();defer{lock.unlock()};guard allowed(remote) else{return false}
        let local=try observe(remote.path)
        if let local,local.hash==remote.hash,local.deleted==remote.deleted {var merged=local;merged.clock=local.merged(remote);if merged.clock != local.clock {try record(merged)};return false}
        if let local,local.dominates(remote){return false}
        if remote.deleted {try apply(remote,temporary:nil);return false}
        // Reuse an already verified local copy when the same paper is filed in
        // more than one folder. Each destination remains an independent file.
        for row in try db.execute("SELECT path FROM entries WHERE hash=? AND size=? AND deleted=0 AND path<>? LIMIT 4",[remote.hash,remote.size,remote.path]) {
            guard let path=row["path"] as? String,store.rules.includes(path),let candidate=try? store.safeURL(path),let hash=try? Self.digest(candidate),hash==remote.hash else{continue}
            try apply(remote,temporary:candidate);return false
        }
        return true
    }
    private func record(_ e:SyncEntry)throws {
        let v=try? store.safeURL(e.path).resourceValues(forKeys:[.contentModificationDateKey]);try put(e,modified:v?.contentModificationDate?.timeIntervalSince1970 ?? 0)
    }
    public func staging(_ e:SyncEntry)throws->URL {
        guard allowed(e),!e.deleted else{throw VaultError.message("Invalid transfer")}
        let folder=store.metadata.appendingPathComponent("sync/incoming");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let url=folder.appendingPathComponent(VaultStore.fingerprint(Data((e.path+e.hash).utf8))+".partial")
        let partial=(try? FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.intValue ?? 0
        let free=(try? FileManager.default.attributesOfFileSystem(forPath:folder.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? Int64.max
        guard Int64(max(0,e.size-partial))+64*1024*1024<free else{throw VaultError.message("Not enough free space to receive this document. Existing files are safe.")}

        if (try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize)==e.size,try Self.digest(url) != e.hash {let f=try FileHandle(forWritingTo:url);try f.truncate(atOffset:0);try f.close()}
        return url
    }
    public func apply(_ remote:SyncEntry,temporary:URL?)throws {
        lock.lock();defer{lock.unlock()}
        guard allowed(remote) else{throw VaultError.message("This peer offered an excluded or invalid document")}
        try store.withMutation {
            let local=try observe(remote.path)
            if let local,local.dominates(remote),!(local.hash==remote.hash && local.deleted==remote.deleted){return}
            if let local,local.hash==remote.hash,local.deleted==remote.deleted {var merged=local;merged.clock=local.merged(remote);try record(merged);return}
            if !remote.deleted {guard let temporary,try Self.digest(temporary)==remote.hash,(try FileManager.default.attributesOfItem(atPath:temporary.path)[.size] as? NSNumber)?.intValue==remote.size else{throw VaultError.message("Transfer checksum did not match. Original document kept.")}}
            var final=remote
            if let local {final.clock=local.merged(remote)}
            let concurrent=local.map{!remote.dominates($0)} ?? false
            if concurrent,let local {
                // Delete/edit conflicts keep the live document. Edit/edit conflicts choose
                // a deterministic primary and retain the other as an ordinary visible file.
                if remote.deleted {var kept=local;kept.clock=final.clock;try record(kept);return}
                if !local.deleted {
                    let remoteWins=remote.hash<local.hash
                    let losingHash=remoteWins ? local.hash:remote.hash
                    let ext=(remote.path as NSString).pathExtension,stem=(remote.path as NSString).deletingPathExtension
                    let conflict=stem+" (sync conflict "+losingHash.prefix(12)+")."+ext
                    let losingURL=remoteWins ? try store.safeURL(local.path):temporary!
                    let conflictURL=try store.safeURL(conflict)
                    if !FileManager.default.fileExists(atPath:conflictURL.path) {try store.replaceFromSync(path:conflict,source:losingURL);try observe(conflict)}
                    if !remoteWins {var kept=local;kept.clock=final.clock;try record(kept);return}
                }
            }
            if final.deleted {if let local,!local.deleted {try store.removeFromSync(path:remote.path)}}else{try store.replaceFromSync(path:remote.path,source:temporary!)}
            try record(final)
        }
    }
}

extension VaultStore {
    func withMutation<T>(_ body:()throws->T)rethrows->T {mutationLock.lock();defer{mutationLock.unlock()};return try body()}
    private func archiveForSync(_ path:String)throws {
        let url=try safeURL(path);guard FileManager.default.fileExists(atPath:url.path)else{return}
        let dir=metadata.appendingPathComponent("recovery/"+Self.fingerprint(Data(path.utf8)))
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        try Data(path.utf8).write(to:dir.appendingPathComponent("path.txt"),options:.atomic)
        try FileManager.default.copyItem(at:url,to:dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970*1000))-\(UUID().uuidString).snapshot"))
    }
    func replaceFromSync(path:String,source:URL)throws {
        let target=try safeURL(path);try archiveForSync(path)
        try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
        let staged=target.deletingLastPathComponent().appendingPathComponent(".archii-transfer-"+UUID().uuidString)
        try FileManager.default.copyItem(at:source,to:staged);defer{try? FileManager.default.removeItem(at:staged)}
        guard rename(staged.path,target.path)==0 else{throw VaultError.message("Could not install synced file; original retained")}
        try refreshPaths([path])
    }
    func removeFromSync(path:String)throws {try archiveForSync(path);let target=metadata.appendingPathComponent("trash/\(UUID().uuidString)/"+path);try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true);try FileManager.default.moveItem(at:safeURL(path),to:target);try refreshPaths([path])}
}
