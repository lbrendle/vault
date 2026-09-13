import Foundation
import VaultCore

/// All windows share one download; progress remains available when navigating.
@MainActor final class StarterDownloads {
    static let shared = StarterDownloads()
    private var task: Task<Void, Never>?
    private(set) var state: [String: Any] = [:]
    var onChange: (([String: Any]) -> Void)?
    private var resources: URL { Bundle.main.resourceURL! }
    func catalog() throws -> [String: Any] {
        ["models": try StarterModel.catalog(at: resources.appendingPathComponent("starter-models.json")).map(\.json), "download": state]
    }
    func pause() { task?.cancel() }
    func start(_ id: String) throws {
        guard task == nil else { throw VaultError.message("A model is already downloading. Pause it before starting another.") }
        let models = try StarterModel.catalog(at: resources.appendingPathComponent("starter-models.json"))
        guard let model = models.first(where: { $0.id == id }) else { throw VaultError.message("Unknown starter model") }
        state = ["id": id, "status": "downloading", "received": 0, "total": model.bytes, "file": "Preparing…"]
        onChange?(state)
        let resources = self.resources
        task = Task {
            do {
                // File validation and writes stay off the UI thread.
                let relay=DownloadProgressRelay { received,total,file in
                    Task { @MainActor in
                        guard self.state["id"] as? String==id,self.state["status"] as? String=="downloading" else{return}
                        self.state=["id":id,"status":"downloading","received":received,"total":total,"file":file]
                        self.onChange?(self.state)
                    }
                }
                let worker = Task.detached(priority: .utility) {
                    try await StarterModelInstaller.install(model, root: ModelLibrary.root, notices: resources) { received,total,file in
                        relay.update(received,total,file)
                    }
                }
                let folder = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                UserDefaults.standard.set(folder.lastPathComponent, forKey: "selectedModel")
                self.state = ["id": id, "status": "ready", "received": model.bytes, "total": model.bytes]
            } catch is CancellationError {
                self.state["status"] = "paused"
            } catch {
                self.state["status"] = "error"; self.state["message"] = error.localizedDescription
            }
            self.task = nil; self.onChange?(self.state)
        }
    }
}

private final class DownloadProgressRelay: @unchecked Sendable {
    private let lock=NSLock()
    private var lastBytes:Int64 = -1
    private var lastFile=""
    private let emit:@Sendable(Int64,Int64,String)->Void
    init(emit:@escaping @Sendable(Int64,Int64,String)->Void){self.emit=emit}
    func update(_ bytes:Int64,_ total:Int64,_ file:String) {
        lock.lock()
        let changed=bytes-lastBytes>2*1024*1024 || file != lastFile || bytes==total
        if changed{lastBytes=bytes;lastFile=file}
        lock.unlock()
        if changed{emit(bytes,total,file)}
    }
}
