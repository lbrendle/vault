import Foundation
import VaultCore

/// Bridges the Python worker to the same offline model runtime as Vault chat.
/// Never called on the main thread; no HTTP server or model downloads are involved.
enum LabModel {
    private static let lock=NSLock()
    private static var active:LocalModel?
    static func cancel(){lock.lock();let model=active;lock.unlock();DispatchQueue.main.async{model?.stop()}}
    private static func encode(_ value:[String:Any])->String {
        guard let data=try? JSONSerialization.data(withJSONObject:value,options:.sortedKeys) else{return "{\"error\":\"Invalid model response\"}"}
        return String(decoding:data,as:UTF8.self)
    }
    private final class Response:@unchecked Sendable {
        let lock=NSLock(),done=DispatchSemaphore(value:0)
        var text="",failure:String?,metadata=[String:Any]()
        func event(_ event:[String:Any]) {
            lock.lock();defer{lock.unlock()}
            let data=event["data"] as? [String:Any] ?? [:]
            switch event["event"] as? String {
            case "delta":text+=data["text"] as? String ?? ""
            case "error":failure=data["message"] as? String ?? "Local generation failed"
            case "complete":metadata=data;if data["status"] as? String=="stopped"{failure="Local generation stopped"}
            case "unloaded":done.signal()
            default:break
            }
        }
        func rejected(_ error:String){lock.lock();failure=error;lock.unlock();done.signal()}
        func result()->[String:Any]{lock.lock();defer{lock.unlock()};if let failure{return ["error":failure]};return ["text":text,"local":true,"offline":true,"metadata":metadata]}
    }
    static func dispatch(_ input:String)->String {
        do {
            guard !Thread.isMainThread,input.utf8.count<=256*1024,
                  var args=try JSONSerialization.jsonObject(with:Data(input.utf8)) as? [String:Any] else{throw VaultError.message("Invalid local model request")}
            let catalog=ModelLibrary.catalog(),models=catalog["models"] as? [[String:Any]] ?? []
            if args["method"] as? String=="list"{return encode(["models":models,"local":true,"offline":true])}
            guard args["method"] as? String=="generate" else{throw VaultError.message("Unknown local model operation")}
            let saved=UserDefaults.standard.string(forKey:"selectedModel") ?? ""
            let selected=models.first(where:{$0["id"] as? String==saved}) ?? models.first(where:{$0["recommended"] as? Bool==true}) ?? models.first
            if (args["model_id"] as? String ?? "").isEmpty{args["model_id"]=selected?["id"] as? String ?? ""}
            guard !models.isEmpty else{throw VaultError.message("Install a local model in Vault Settings → Models & chat. Once installed, notebooks use it offline.")}
            let response=Response(),runner=LocalModel(emit:response.event)
            lock.lock();if active != nil{lock.unlock();throw VaultError.message("A notebook is already using a local model")};active=runner;lock.unlock()
            defer{lock.lock();active=nil;lock.unlock()}
            let request=args
            DispatchQueue.main.async{runner.call(request){_,error in if let error{response.rejected(error)}}}
            let timeout=min(600,max(1,args["timeout"] as? Int ?? 120))
            guard response.done.wait(timeout:.now()+Double(timeout)) == .success else{DispatchQueue.main.async{runner.stop()};throw VaultError.message("Local model generation exceeded \(timeout) seconds and was stopped.")}
            return encode(response.result())
        }catch{return encode(["error":error.localizedDescription])}
    }
}
