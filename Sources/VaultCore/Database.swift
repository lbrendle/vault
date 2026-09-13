import Foundation
import CSQLite

public enum VaultError: Error, LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public init(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw VaultError.message("Cannot open local index") }
        sqlite3_busy_timeout(handle, 5000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA cache_size=-12000")
        try execute("PRAGMA foreign_keys=ON")
        try execute("CREATE TABLE IF NOT EXISTS docs (id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, parent TEXT NOT NULL, title TEXT NOT NULL, ext TEXT NOT NULL, size INTEGER NOT NULL, modified REAL NOT NULL, body TEXT NOT NULL DEFAULT '', frontmatter TEXT NOT NULL DEFAULT '', generation INTEGER NOT NULL DEFAULT 0)")
        try execute("CREATE INDEX IF NOT EXISTS docs_parent ON docs(parent,title COLLATE NOCASE)")
        try execute("CREATE INDEX IF NOT EXISTS docs_title ON docs(title COLLATE NOCASE)")
        try execute("CREATE INDEX IF NOT EXISTS docs_metadata ON docs(path,title,ext,size,modified,parent)")
        try execute("CREATE INDEX IF NOT EXISTS docs_recent ON docs(modified DESC,path,title,ext,size)")
        try execute("CREATE INDEX IF NOT EXISTS docs_generation ON docs(generation)")
        try execute("CREATE INDEX IF NOT EXISTS docs_modified ON docs(modified DESC)")
        try execute("CREATE VIRTUAL TABLE IF NOT EXISTS search USING fts5(path, title, body, content='docs', content_rowid='id', tokenize='unicode61 remove_diacritics 2')")
        try execute("CREATE TRIGGER IF NOT EXISTS docs_ai AFTER INSERT ON docs BEGIN INSERT INTO search(rowid,path,title,body) VALUES(new.id,new.path,new.title,new.body); END")
        try execute("CREATE TRIGGER IF NOT EXISTS docs_ad AFTER DELETE ON docs BEGIN INSERT INTO search(search,rowid,path,title,body) VALUES('delete',old.id,old.path,old.title,old.body); END")
        try execute("CREATE TRIGGER IF NOT EXISTS docs_au AFTER UPDATE OF path,title,body ON docs BEGIN INSERT INTO search(search,rowid,path,title,body) VALUES('delete',old.id,old.path,old.title,old.body); INSERT INTO search(rowid,path,title,body) VALUES(new.id,new.path,new.title,new.body); END")
        try execute("CREATE TABLE IF NOT EXISTS links(source TEXT NOT NULL, target TEXT NOT NULL, PRIMARY KEY(source,target))")
        try execute("CREATE INDEX IF NOT EXISTS links_target ON links(target)")
        try execute("CREATE TABLE IF NOT EXISTS tags(source TEXT NOT NULL, tag TEXT NOT NULL, PRIMARY KEY(source,tag))")
        try execute("CREATE INDEX IF NOT EXISTS tags_tag ON tags(tag)")
    }
    deinit { sqlite3_close(handle) }
    @discardableResult public func execute(_ sql: String, _ args: [Any] = []) throws -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        for (index,value) in args.enumerated() {
            let i = Int32(index + 1)
            if let text = value as? String { sqlite3_bind_text(stmt,i,text,-1,transient) }
            else if let n = value as? Int { sqlite3_bind_int64(stmt,i,Int64(n)) }
            else if let n = value as? Int64 { sqlite3_bind_int64(stmt,i,n) }
            else if let n = value as? Double { sqlite3_bind_double(stmt,i,n) }
            else { sqlite3_bind_null(stmt,i) }
        }
        var result: [[String:Any]] = []
        while true {
            let code = sqlite3_step(stmt)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw failure() }
            var row: [String:Any] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                let name = String(cString:sqlite3_column_name(stmt,i))
                switch sqlite3_column_type(stmt,i) {
                case SQLITE_INTEGER: row[name] = Int(sqlite3_column_int64(stmt,i))
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(stmt,i)
                case SQLITE_TEXT: row[name] = String(cString:sqlite3_column_text(stmt,i))
                default: row[name] = NSNull()
                }
            }
            result.append(row)
        }
        return result
    }
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do { let value = try body(); try execute("COMMIT"); return value }
        catch { _ = try? execute("ROLLBACK"); throw error }
    }
    private func failure() -> Error { VaultError.message(String(cString:sqlite3_errmsg(handle))) }
}
