import Foundation
import VaultCore
#if os(macOS)
enum PairedModel {
 static func serve(channel:PeerChannel,args:[String:Any])async throws {
  var args=args
  if (args["model_id"] as? String ?? "").isEmpty {
   let models=ModelLibrary.catalog()["models"] as? [[String:Any]] ?? []
   let saved=UserDefaults.standard.string(forKey:"selectedModel") ?? ""
   let selected=models.first(where:{$0["id"] as? String==saved}) ?? models.first(where:{$0["recommended"] as? Bool==true}) ?? models.first
   args["model_id"]=selected?["id"] as? String ?? ""
  }
  let (events,continuation)=AsyncStream<[String:Any]>.makeStream()
  let request=args
  let model=LocalModel{event in continuation.yield(event);if event["event"] as? String=="unloaded"{continuation.finish()}}
  await MainActor.run {model.call(request){_,error in if let error {continuation.yield(["event":"error","data":["message":error]]);continuation.yield(["event":"unloaded","data":[:]]);continuation.finish()}}}
  do{for await event in events {try await channel.send(["model":event])}}catch{model.stop();continuation.finish();throw error}
 }
}
#endif
