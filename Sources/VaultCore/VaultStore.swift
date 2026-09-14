import Foundation
import CryptoKit

public struct VaultRules: Codable, Sendable {
    public static let codeExtensions = ["py","pyi","ipynb","js","jsx","ts","tsx","swift","c","h","cpp","hpp","rs","go","r","jl","sh","bash","zsh","sql","m","mm","metal","html","css","json","jsonl","toml","yaml","yml","csv","tsv","npy","npz"]
    public var excludedDirectories: [String] = ["node_modules","__pycache__","venv","env",".venv","target","dist","build","coverage","DerivedData","Pods","Carthage"]
    public var excludedPaths: [String] = []
    public var documentExtensions = Array(Set(["md","markdown","txt","pdf","canvas","base","docx","doc","pptx","xlsx","odt","ods","odp","rtf","epub","png","jpg","jpeg","gif","svg","webp","heic","mp3","m4a","wav","mp4","mov"] + codeExtensions)).sorted()
    // Missing in older rules files. Migrate once so later explicit extension
    // exclusions survive reopening a vault, regardless of the Lab toggle.
    public var codeDiscoveryVersion: Int? = 1
    public init() {}
    public func includes(_ path: String, directory: Bool = false) -> Bool {
        let parts = path.split(separator:"/").map(String.init)
        if parts.contains(where: { $0.hasPrefix(".") || excludedDirectories.contains($0) }) { return false }
        if excludedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return false }
        return directory || documentExtensions.contains((path as NSString).pathExtension.lowercased())
    }
}

/// Apply the same normalization to bundle roots and assets before checking containment.
public enum VaultAsset {
    public static func url(path:String,root:URL)throws->URL {
        let decoded=path.removingPercentEncoding ?? path
        guard !decoded.contains("\0"),!decoded.split(separator:"/").contains("..") else{throw VaultError.message("Invalid asset")}
        let base=root.standardizedFileURL
        let relative=decoded.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        let target=base.appendingPathComponent(relative.isEmpty ? "index.html":relative).standardizedFileURL
        guard target.path.hasPrefix(base.path+"/") else{throw VaultError.message("Invalid asset")}
        return target
    }
}

/// Persist app-owned folders relative to Documents: iOS can relocate its container on update.
public enum LocalVaultReference {
    public static func relative(_ root:URL, documents:URL) -> String? {
        let base=documents.standardizedFileURL.resolvingSymlinksInPath().path
        let path=root.standardizedFileURL.resolvingSymlinksInPath().path
        if path==base{return "."}
        guard path.hasPrefix(base+"/") else{return nil}
        return String(path.dropFirst(base.count+1))
    }
    public static func resolve(_ relative:String, documents:URL) -> URL? {
        if relative=="."{return documents}
        guard !relative.isEmpty,!relative.hasPrefix("/"),!relative.contains("\0"),
              !relative.split(separator:"/").contains(where:{$0==".." || $0=="."}) else{return nil}
        return documents.appendingPathComponent(relative,isDirectory:true)
    }
}

public final class VaultStore: @unchecked Sendable {
    public let root: URL
    public let db: Database
    public let cache:URL
    public let metadata: URL
    public var rules: VaultRules
    let mutationLock = NSRecursiveLock()
    private let scanLock = NSLock()
    private let statusLock = NSLock()
    private var scanState: [String:Any] = ["running":false,"visited":0,"updated":0,"skippedDirectories":0]
    public init(root: URL, cache: URL) throws {
        guard let physical = realpath(root.path, nil) else { throw VaultError.message("Vault path is unavailable") }
        self.root = URL(fileURLWithPath:String(cString:physical),isDirectory:true)
        free(physical)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath:self.root.path,isDirectory:&isDirectory), isDirectory.boolValue else { throw VaultError.message("Choose an existing vault folder") }
        metadata = self.root.appendingPathComponent(".archii-vault",isDirectory:true)
        let rulesURL = metadata.appendingPathComponent("rules.json")
        if let data = try? Data(contentsOf:rulesURL), let saved = try? JSONDecoder().decode(VaultRules.self,from:data) { rules = saved } else { rules = VaultRules() }
        self.cache=cache
        db = try Database(cache.appendingPathComponent("index.sqlite"))
        if rules.codeDiscoveryVersion == nil {
            rules.documentExtensions = Array(Set(rules.documentExtensions + VaultRules.codeExtensions)).sorted()
            rules.codeDiscoveryVersion = 1
            // Discovery still works when the selected folder cannot persist metadata.
            try? saveRules(rules)
        }
    }
    public static func fingerprint(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    public func safeURL(_ relative: String, requireDocument: Bool = true) throws -> URL {
        guard !relative.hasPrefix("/"), !relative.split(separator:"/").contains(".."), !relative.contains("\0"), rules.includes(relative,directory: !requireDocument) else { throw VaultError.message("This path is outside the document library or excluded by its rules") }
        let url = root.appendingPathComponent(relative)
        var current = root
        for component in relative.split(separator:"/") {
            current = current.appendingPathComponent(String(component))
            if (try? FileManager.default.destinationOfSymbolicLink(atPath:current.path)) != nil {
                throw VaultError.message("Symbolic links are excluded from the document library")
            }
        }
        return url
    }
    public func status() -> [String:Any] {
        statusLock.lock(); var out=scanState; statusLock.unlock()
        out["count"] = (try? db.execute("SELECT count(*) AS n FROM docs").first?["n"]) ?? 0
        out["name"] = root.lastPathComponent; out["root"] = root.path
        return out
    }
    private func progress(_ value:[String:Any]) { statusLock.lock(); scanState=value; statusLock.unlock() }
    public func scan() throws -> [String:Any] {
        guard scanLock.try() else { return status() }; defer { scanLock.unlock() }
        let started=Date(), generation=try nextGeneration()
        var visited=0, updated=0, skipped=0, errors=[String](), batch=[(String,URL,URLResourceValues)]()
        var scanComplete=true
        progress(["running":true,"visited":0,"updated":0,"skippedDirectories":0])
        defer { progress(["running":false,"visited":visited,"updated":updated,"skippedDirectories":skipped,"errors":errors,"seconds":Date().timeIntervalSince(started),"complete":scanComplete]) }
        let keys: [URLResourceKey] = [.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey]
        guard let iterator=FileManager.default.enumerator(at:root,includingPropertiesForKeys:keys,options:[],errorHandler:{url,error in scanComplete=false; if errors.count<20 {errors.append(url.lastPathComponent+": "+error.localizedDescription)}; return true}) else { throw VaultError.message("Cannot scan this folder") }
        func flush() throws {
            mutationLock.lock(); defer { mutationLock.unlock() }
            try db.transaction {
                for (path,url,v) in batch {
                    let size=v.fileSize ?? 0, modified=v.contentModificationDate?.timeIntervalSince1970 ?? 0
                    let old=try db.execute("SELECT size,modified FROM docs WHERE path=?",[path]).first
                    if old?["size"] as? Int == size, old?["modified"] as? Double == modified {
                        try db.execute("UPDATE docs SET generation=? WHERE path=?",[generation,path]); continue
                    }
                    do { try autoreleasepool {try index(path:path,url:url,size:size,modified:modified,generation:generation)}; updated += 1 }
                    catch { scanComplete=false; if errors.count<20 { errors.append(path+": "+error.localizedDescription) } }
                }
            }
            batch.removeAll(keepingCapacity:true)
            progress(["running":true,"visited":visited,"updated":updated,"skippedDirectories":skipped,"seconds":Date().timeIntervalSince(started)])
        }
        for case let url as URL in iterator {
            let path=String(url.path.dropFirst(root.path.count+1))
            let v:URLResourceValues
            do { v=try url.resourceValues(forKeys:Set(keys)) } catch {scanComplete=false; continue}
            if v.isSymbolicLink == true { iterator.skipDescendants(); skipped += 1; continue }
            if v.isDirectory == true { if !rules.includes(path,directory:true) { iterator.skipDescendants(); skipped += 1 }; continue }
            guard rules.includes(path) else { continue }
            visited += 1; batch.append((path,url,v))
            if batch.count>=128 { try flush() }
        }
        try flush()
        // A failed/unavailable subtree must never look like mass deletion.
        if scanComplete {
            try db.transaction {
                try db.execute("DELETE FROM links WHERE source IN (SELECT path FROM docs WHERE generation<?)",[generation])
                try db.execute("DELETE FROM tags WHERE source IN (SELECT path FROM docs WHERE generation<?)",[generation])
                try db.execute("DELETE FROM docs WHERE generation<?",[generation])
            }
        }
        return ["visited":visited,"updated":updated,"skippedDirectories":skipped,"seconds":Date().timeIntervalSince(started),"complete":scanComplete,"errors":errors]
    }
    private func nextGeneration() throws -> Int {
        let previous=(try db.execute("SELECT MAX(generation) AS n FROM docs").first?["n"] as? Int) ?? 0
        return max(Int(Date().timeIntervalSince1970*1000),previous+1)
    }
    private func index(path:String,url:URL,size:Int,modified:Double,generation:Int) throws {
        let ext=url.pathExtension.lowercased()
        var body=""
        if ["md","markdown","txt","canvas","base"].contains(ext) {
            guard size <= 64*1024*1024 else { throw VaultError.message("Text larger than 64 MiB requires a streaming reader; kept on disk") }
            body=(try? String(contentsOf:url,encoding:.utf8)) ?? ""
        }
        if ext=="ipynb",size<=64*1024*1024,let data=try? Data(contentsOf:url),let book=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let cells=book["cells"] as? [[String:Any]] {
            body=cells.filter{$0["cell_type"] as? String=="markdown"}.compactMap{cell in (cell["source"] as? String) ?? (cell["source"] as? [String])?.joined()}.joined(separator:"\n\n")
        }
        var frontmatter=""
        if body.hasPrefix("---\n"), let range=body.range(of:"\n---",range:body.index(body.startIndex,offsetBy:4)..<body.endIndex) { frontmatter=String(body[body.index(body.startIndex,offsetBy:4)..<range.lowerBound]) }
        try db.execute("INSERT INTO docs(path,parent,title,ext,size,modified,body,frontmatter,generation) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET parent=excluded.parent,title=excluded.title,ext=excluded.ext,size=excluded.size,modified=excluded.modified,body=excluded.body,frontmatter=excluded.frontmatter,generation=excluded.generation",[path,(path as NSString).deletingLastPathComponent,url.deletingPathExtension().lastPathComponent,ext,size,modified,body,frontmatter,generation])
        try db.execute("DELETE FROM links WHERE source=?",[path]); try db.execute("DELETE FROM tags WHERE source=?",[path])
        guard ["md","markdown","ipynb"].contains(ext) else { return }
        let text=body as NSString
        let linkRE=try NSRegularExpression(pattern:#"\[\[([^\]\n]+)\]\]|\]\(([^\)\n]+)\)"#)
        var targets=Set<String>()
        for m in linkRE.matches(in:body,range:NSRange(location:0,length:text.length)) {
            let range=m.range(at:m.range(at:1).location != NSNotFound ? 1:2)
            let raw=text.substring(with:range).components(separatedBy:"|")[0].components(separatedBy:"#")[0].trimmingCharacters(in:.whitespaces)
            if !raw.isEmpty && !raw.contains("://") { targets.insert(raw.removingPercentEncoding ?? raw) }
        }
        for target in targets {try db.execute("INSERT OR IGNORE INTO links(source,target) VALUES(?,?)",[path,target])}
        let tagRE=try NSRegularExpression(pattern:#"(?:^|\s)#([\p{L}_][\p{L}\p{N}_/\-]*)"#,options:.anchorsMatchLines)
        var tags=Set(tagRE.matches(in:body,range:NSRange(location:0,length:text.length)).map{text.substring(with:$0.range(at:1))})
        if let re=try? NSRegularExpression(pattern:#"(?m)^tags:\s*\[([^\]]*)\]"#), let m=re.firstMatch(in:frontmatter,range:NSRange(location:0,length:(frontmatter as NSString).length)) {
            for tag in (frontmatter as NSString).substring(with:m.range(at:1)).split(separator:",") { let value=tag.trimmingCharacters(in:CharacterSet(charactersIn:" \"'#")); if !value.isEmpty {tags.insert(value)} }
        }
        for tag in tags {try db.execute("INSERT OR IGNORE INTO tags(source,tag) VALUES(?,?)",[path,tag])}
    }
    public func list(parent:String="",offset:Int=0) throws -> [[String:Any]] {
        guard offset>=0 else {throw VaultError.message("Invalid folder page")}
        if !parent.isEmpty {_ = try safeURL(parent,requireDocument:false)}
        let url=root.appendingPathComponent(parent)
        let children=try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:[])
        // Browsing must work before full-text indexing finishes, including
        // files just synced or edited by another app. Never take the index lock.
        var folders=[[String:Any]](),files=[URL]()
        for child in children {
            guard let v=try? child.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey]),v.isSymbolicLink != true else {continue}
            let path=parent.isEmpty ? child.lastPathComponent:parent+"/"+child.lastPathComponent
            if v.isDirectory==true {
                if offset==0 && rules.includes(path,directory:true) {folders.append(["path":path,"title":child.lastPathComponent,"directory":true])}
            } else if rules.includes(path) {files.append(child)}
        }
        folders.sort{($0["title"] as! String).localizedStandardCompare($1["title"] as! String) == .orderedAscending}
        files.sort{$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending}
        let page:[[String:Any]]=files.dropFirst(offset).prefix(200).map{child in
            let values=try? child.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
            return ["path":parent.isEmpty ? child.lastPathComponent:parent+"/"+child.lastPathComponent,"title":child.deletingPathExtension().lastPathComponent,"ext":child.pathExtension.lowercased(),"size":values?.fileSize ?? 0,"modified":values?.contentModificationDate?.timeIntervalSince1970 ?? 0]
        }
        return folders + page
    }
    public func search(_ query:String, offset:Int=0) throws -> [[String:Any]] {
        if query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {return try db.execute("SELECT path,title,ext,size,modified FROM docs ORDER BY modified DESC LIMIT 80 OFFSET ?",[offset])}
        var clauses=[String](), args=[Any](), terms=[String]()
        let re=try NSRegularExpression(pattern:#"(?:[^\s\"]+|\"[^\"]*\")+"#); let ns=query as NSString
        for m in re.matches(in:query,range:NSRange(location:0,length:ns.length)) {
            let token=ns.substring(with:m.range)
            if token.hasPrefix("path:") || token.hasPrefix("file:") {
                let path=String(token.dropFirst(5)).trimmingCharacters(in:CharacterSet(charactersIn:"\"")); clauses.append("d.path LIKE ? ESCAPE '\\'"); args.append("%"+escapeLike(path)+"%")
            } else if token.hasPrefix("tag:") { clauses.append("d.path IN (SELECT source FROM tags WHERE tag=? OR tag LIKE ? ESCAPE '\\')"); let tag=String(token.dropFirst(4)).trimmingCharacters(in:CharacterSet(charactersIn:"#\"")); args.append(tag);args.append(escapeLike(tag)+"/%") }
            else {let term=token.trimmingCharacters(in:CharacterSet(charactersIn:"\"")); if !term.isEmpty {terms.append("\""+term.replacingOccurrences(of:"\"",with:"\"\"")+"\"")}}
        }
        let metadata="d.path,d.title,d.ext,d.size,d.modified"
        if !terms.isEmpty {
            clauses.insert("search MATCH ?",at:0); args.insert(terms.joined(separator:" AND "),at:0);args.append(offset)
            return try db.execute("SELECT \(metadata),snippet(search,2,'','', ' … ',32) AS snippet FROM search JOIN docs d ON d.id=search.rowid WHERE \(clauses.joined(separator:" AND ")) ORDER BY bm25(search,3,5,1) LIMIT 80 OFFSET ?",args)
        }
        args.append(offset)
        return try db.execute("SELECT \(metadata) FROM docs d INDEXED BY docs_metadata WHERE \(clauses.isEmpty ? "1":clauses.joined(separator:" AND ")) ORDER BY d.modified DESC LIMIT 80 OFFSET ?",args)
    }
    private func escapeLike(_ value:String)->String {value.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"%",with:"\\%").replacingOccurrences(of:"_",with:"\\_")}
    public func read(_ path:String) throws -> [String:Any] {
        let url=try safeURL(path), values=try url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
        var out:[String:Any]=["path":path,"title":url.deletingPathExtension().lastPathComponent,"ext":url.pathExtension.lowercased(),"size":values.fileSize ?? 0]
        if ["md","markdown","txt","canvas","base"].contains(url.pathExtension.lowercased()) {
            guard (values.fileSize ?? 0)<64*1024*1024 else {throw VaultError.message("This text exceeds the current 64 MiB editor limit")}
            let data=try Data(contentsOf:url); guard let content=String(data:data,encoding:.utf8) else {throw VaultError.message("This document is not UTF-8")}
            out["content"]=content; out["revision"]=Self.fingerprint(data)
        }
        return out
    }
    /// Bounded local reads let PDF pages load without copying the whole attachment.
    public func pdfRange(_ path:String,offset:Int,length:Int,version:String? = nil) throws -> [String:Any] {
        let url=try safeURL(path)
        guard url.pathExtension.lowercased()=="pdf",offset>=0,length>0,length<=1024*1024 else {throw VaultError.message("Invalid PDF byte range")}
        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
        let size=try handle.seekToEnd()
        let values=try url.resourceValues(forKeys:[.contentModificationDateKey])
        let current="\(size):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        guard version==nil || version==current else{throw VaultError.message("This PDF changed. Reopen it to read the updated document.")}
        guard UInt64(offset)<=size else{throw VaultError.message("PDF range is outside the document")}
        try handle.seek(toOffset:UInt64(offset))
        let data=try handle.read(upToCount:min(length,Int(size)-offset)) ?? Data()
        return ["data":data.base64EncodedString(),"size":size,"version":current]
    }
    public func save(_ path:String,content:String,revision:String?) throws -> [String:Any] {
        mutationLock.lock(); defer {mutationLock.unlock()}
        let url=try safeURL(path)
        guard ["md","markdown","txt","canvas","base"].contains(url.pathExtension.lowercased()) else {throw VaultError.message("This format is read-only")}
        let fm=FileManager.default
        if fm.fileExists(atPath:url.path) {
            let old=try Data(contentsOf:url)
            guard revision==Self.fingerprint(old) else {throw VaultError.message("This file changed outside Vault. Your draft is retained. Reload the current file or save the draft as a new note.")}
            if old==Data(content.utf8) {return try read(path)}
            try snapshot(path,data:old)
        } else if revision != nil {throw VaultError.message("This file was moved or deleted outside Vault. Save your draft as a new note.")}
        try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(content.utf8).write(to:url,options:.atomic)
        let v=try url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
        try db.transaction {try index(path:path,url:url,size:v.fileSize ?? 0,modified:v.contentModificationDate!.timeIntervalSince1970,generation:try nextGeneration())}
        return try read(path)
    }
    private func snapshot(_ path:String,data:Data) throws {
        let dir=metadata.appendingPathComponent("recovery").appendingPathComponent(Self.fingerprint(Data(path.utf8)))
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        try Data(path.utf8).write(to:dir.appendingPathComponent("path.txt"),options:.atomic)
        try data.write(to:dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970*1000))-\(UUID().uuidString).snapshot"),options:.atomic)
    }
    public func recovery(_ path:String) throws -> [[String:Any]] {
        _ = try safeURL(path)
        let dir=metadata.appendingPathComponent("recovery").appendingPathComponent(Self.fingerprint(Data(path.utf8)))
        return ((try? FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:[.fileSizeKey])) ?? []).filter{$0.pathExtension=="snapshot"}.sorted{$0.lastPathComponent>$1.lastPathComponent}.prefix(100).map{["id":$0.lastPathComponent,"size":(try? $0.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0]}
    }
    public func recoveryRead(_ path:String,id:String) throws -> String {
        _ = try safeURL(path); guard id==URL(fileURLWithPath:id).lastPathComponent, id.hasSuffix(".snapshot") else {throw VaultError.message("Invalid snapshot")}
        return try String(contentsOf:metadata.appendingPathComponent("recovery").appendingPathComponent(Self.fingerprint(Data(path.utf8))).appendingPathComponent(id),encoding:.utf8)
    }
    public func trash(_ path:String,revision:String?) throws {
        mutationLock.lock();defer{mutationLock.unlock()}
        let url=try safeURL(path); let data=try Data(contentsOf:url)
        guard revision==Self.fingerprint(data) else {throw VaultError.message("File changed; reload before deleting")}
        try snapshot(path,data:data)
        let target=metadata.appendingPathComponent("trash/\(UUID().uuidString)/\(path)")
        try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
        try FileManager.default.moveItem(at:url,to:target)
        try db.transaction {try db.execute("DELETE FROM links WHERE source=?",[path]);try db.execute("DELETE FROM tags WHERE source=?",[path]);try db.execute("DELETE FROM docs WHERE path=?",[path])}
    }
    public func resolve(_ target:String,from:String="") throws -> [[String:Any]] {
        let clean=(target.removingPercentEncoding ?? target).components(separatedBy:"#")[0].components(separatedBy:"|")[0]
        if clean.isEmpty {return try db.execute("SELECT path,title,ext FROM docs WHERE path=?",[from])}
        let parent=(from as NSString).deletingLastPathComponent
        let relative=(parent.isEmpty ? clean:parent+"/"+clean)
        for candidate in [relative,relative+".md",clean,clean+".md"] {
            let normalized=URL(fileURLWithPath:"/"+candidate).standardizedFileURL.path.dropFirst()
            let found=try db.execute("SELECT path,title,ext FROM docs WHERE path=?",[String(normalized)])
            if !found.isEmpty {return found}
            // A newly synced or newly enabled code file can be opened before a
            // large vault finishes indexing. Resolve only inside the existing rules.
            if VaultRules.codeExtensions.contains((String(normalized) as NSString).pathExtension.lowercased()),
               let url=try? safeURL(String(normalized)),
               (try? url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true {
                return [["path":String(normalized),"title":url.deletingPathExtension().lastPathComponent,"ext":url.pathExtension.lowercased()]]
            }
        }
        let name=((clean as NSString).lastPathComponent as NSString).deletingPathExtension
        let ext=(clean as NSString).pathExtension.lowercased()
        if !ext.isEmpty{return try db.execute("SELECT path,title,ext FROM docs WHERE title=? COLLATE NOCASE AND ext=? LIMIT 40",[name,ext])}
        return try db.execute("SELECT path,title,ext FROM docs WHERE title=? COLLATE NOCASE LIMIT 40",[name])
    }
    public func backlinks(_ path:String) throws -> [[String:Any]] {
        let name=(path as NSString).lastPathComponent,title=(name as NSString).deletingPathExtension
        let candidates=try db.execute("SELECT DISTINCT source,target FROM links WHERE target IN (?,?,?,?,?) OR target LIKE ? LIMIT 1200",[path,(path as NSString).deletingPathExtension,title,name,title+".md","%/"+name])
        var found=[[String:Any]](),seen=Set<String>()
        for candidate in candidates {
            guard let source=candidate["source"] as? String,let target=candidate["target"] as? String,!seen.contains(source),try resolve(target,from:source).contains(where:{$0["path"] as? String==path}) else{continue}
            if let row=try db.execute("SELECT path,title,ext FROM docs WHERE path=?",[source]).first{found.append(row);seen.insert(source)}
            if found.count>=300{break}
        }
        return found
    }
    /// Keyset pages keep graph data bounded across the native/web bridge. No
    /// document or link count is truncated; the worker resolves links in batches.
    public func graphPage(kind:String,after:Int=0,limit:Int=2048)throws->[String:Any] {
        guard after>=0,limit>0 else{throw VaultError.message("Invalid graph cursor")}
        let count=min(limit,4096),rows:[[String:Any]]
        if kind=="nodes" {rows=try db.execute("SELECT id,path,title FROM docs WHERE id>? ORDER BY id LIMIT ?",[after,count])}
        else if kind=="links" {rows=try db.execute("SELECT rowid AS id,source,target FROM links WHERE rowid>? ORDER BY rowid LIMIT ?",[after,count])}
        else {throw VaultError.message("Invalid graph page")}
        return ["items":rows,"cursor":rows.last?["id"] as? Int ?? after,"more":rows.count==count]
    }
    public func state() throws -> [String:Any] {
        if let data=try? Data(contentsOf:metadata.appendingPathComponent("state.json")), let out=try JSONSerialization.jsonObject(with:data) as? [String:Any] {return out}
        return ["bookmarks":[],"tabs":[],"chats":[],"dailyFolder":"Daily notes","templatesFolder":"Templates"]
    }
    public func saveState(_ value:[String:Any]) throws {
        mutationLock.lock();defer{mutationLock.unlock()}
        try FileManager.default.createDirectory(at:metadata,withIntermediateDirectories:true)
        var merged=sharedMerge(local:try state(),remote:value)
        for (key,item) in value where !["chats","bookmarks","bookmarkChanges"].contains(key){merged[key]=item}
        let data=try JSONSerialization.data(withJSONObject:merged,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:metadata.appendingPathComponent("state.json"),options:.atomic)
    }
    public func saveRules(_ value:VaultRules) throws {
        mutationLock.lock();defer{mutationLock.unlock()}
        try FileManager.default.createDirectory(at:metadata,withIntermediateDirectories:true)
        try JSONEncoder().encode(value).write(to:metadata.appendingPathComponent("rules.json"),options:.atomic);rules=value
    }
    public func move(_ source:String,to destination:String,revision:String) throws -> [String:Any] {
        mutationLock.lock();defer{mutationLock.unlock()}
        let original=try safeURL(source),target=try safeURL(destination)
        guard !FileManager.default.fileExists(atPath:target.path) else{throw VaultError.message("A document already exists at the destination")}
        let initial=try Data(contentsOf:original)
        guard Self.fingerprint(initial)==revision else{throw VaultError.message("The document changed outside Vault; reload before moving it")}
        guard ["md","markdown","canvas","base","txt"].contains(original.pathExtension) else{throw VaultError.message("Attachment moves are not yet supported")}
        let referers=try backlinks(source).compactMap{$0["path"] as? String}
        var edits=[(String,String,String)]()
        let re=try NSRegularExpression(pattern:#"\[\[([^\]\n]+)\]\]|\]\(([^\)\n]+)\)"#)
        for path in Set(referers+[source]) {
            let item=try read(path);guard let text=item["content"] as? String,let rev=item["revision"] as? String else{continue}
            let ns=text as NSString;var updated=text
            for match in re.matches(in:text,range:NSRange(location:0,length:ns.length)).reversed() {
                let wiki=match.range(at:1).location != NSNotFound,range=match.range(at:wiki ? 1:2),raw=ns.substring(with:range)
                let alias=raw.firstIndex(of:"|").map{String(raw[$0...])} ?? ""
                let withoutAlias=raw.components(separatedBy:"|")[0]
                let anchor=withoutAlias.firstIndex(of:"#").map{String(withoutAlias[$0...])} ?? ""
                let name=withoutAlias.components(separatedBy:"#")[0]
                if name.isEmpty || name.contains("://") {continue}
                let found=try resolve(name,from:path)
                guard found.count==1,let resolved=found[0]["path"] as? String else{continue}
                guard resolved==source || path==source else{continue}
                let newPath=resolved==source ? destination:resolved
                var replacement:String
                if wiki {replacement=(newPath.hasSuffix(".md") ? String(newPath.dropLast(3)):newPath)+anchor+alias}
                else {
                    let sourceParent=(path==source ? destination:path).split(separator:"/").dropLast()
                    var from=Array(sourceParent),to=newPath.split(separator:"/").map(String.init)
                    while !from.isEmpty && !to.isEmpty && String(from[0])==to[0] {from.removeFirst();to.removeFirst()}
                    replacement=(Array(repeating:"..",count:from.count)+to).joined(separator:"/").addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!+anchor
                }
                if let swiftRange=Range(range,in:updated){updated.replaceSubrange(swiftRange,with:replacement)}
            }
            if updated != text {edits.append((path,updated,rev))}
        }
        // Preserve every source before performing any move or link rewrite.
        try snapshot(source,data:initial)
        for (path,_,rev) in edits where path != source {
            let data=try Data(contentsOf:safeURL(path));guard Self.fingerprint(data)==rev else{throw VaultError.message("A referring document changed; no move was performed")};try snapshot(path,data:data)
        }
        try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
        try FileManager.default.moveItem(at:original,to:target)
        var completed=[(String,Data,String)]()
        do {
            for (path,text,rev) in edits {
                let effective=path==source ? destination:path
                let old=try Data(contentsOf:safeURL(effective))
                _ = try save(effective,content:text,revision:rev)
                completed.append((effective,old,Self.fingerprint(Data(text.utf8))))
            }
            if !edits.contains(where:{$0.0==source}) {
                let v=try target.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
                try index(path:destination,url:target,size:v.fileSize ?? 0,modified:v.contentModificationDate!.timeIntervalSince1970,generation:try nextGeneration())
            }
            try db.execute("DELETE FROM docs WHERE path=?",[source]);try db.execute("DELETE FROM links WHERE source=?",[source]);try db.execute("DELETE FROM tags WHERE source=?",[source])
            return ["document":try read(destination),"updatedLinksIn":edits.count]
        }catch {
            for (path,data,expected) in completed.reversed() {
                if let current=try? Data(contentsOf:safeURL(path)),Self.fingerprint(current)==expected {try? data.write(to:safeURL(path),options:.atomic)}
            }
            if !FileManager.default.fileExists(atPath:original.path){try? FileManager.default.moveItem(at:target,to:original)}
            throw VaultError.message("Move could not finish. Recovery snapshots preserve affected documents. Recheck the library: "+error.localizedDescription)
        }
    }
    public func refreshPaths(_ paths:[String]) throws {
        mutationLock.lock();defer{mutationLock.unlock()}
        let generation=try nextGeneration()
        for path in Set(paths) {
            guard rules.includes(path) else{continue}
            let url=try safeURL(path)
            if FileManager.default.fileExists(atPath:url.path) {
                let v=try url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey,.isDirectoryKey]);if v.isDirectory==true{continue}
                let old=try db.execute("SELECT size,modified FROM docs WHERE path=?",[path]).first
                if old?["size"] as? Int == v.fileSize,old?["modified"] as? Double == v.contentModificationDate?.timeIntervalSince1970 {continue}
                try db.transaction{try index(path:path,url:url,size:v.fileSize ?? 0,modified:v.contentModificationDate?.timeIntervalSince1970 ?? 0,generation:generation)}
            }else{
                try db.execute("DELETE FROM docs WHERE path=?",[path]);try db.execute("DELETE FROM links WHERE source=?",[path]);try db.execute("DELETE FROM tags WHERE source=?",[path])
            }
        }
    }
    public func folder(_ path:String) throws {let url=try safeURL(path,requireDocument:false);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)}
}
