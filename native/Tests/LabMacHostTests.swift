#if os(macOS)
import XCTest
import VaultCore
@testable import Vault
final class LabMacHostTests:XCTestCase {
 func testPairedLabHost()async throws {
  guard let path=ProcessInfo.processInfo.environment["VAULT_LAB_QA_DIR"],let python=ProcessInfo.processInfo.environment["VAULT_LAB_PYTHON"] else{throw XCTSkip("Set an isolated QA directory and Python environment to run the LAN acceptance test")}
  let qa=URL(fileURLWithPath:path),root=qa.appendingPathComponent("Mac Vault")
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  let oldLab=UserDefaults.standard.object(forKey:"labEnabled");UserDefaults.standard.set(true,forKey:"labEnabled")
  let oldEnabled=UserDefaults.standard.object(forKey:"labHostEnabled"),oldPython=UserDefaults.standard.object(forKey:"labPythonPath")
  UserDefaults.standard.set(python,forKey:"labPythonPath");UserDefaults.standard.set(true,forKey:"labHostEnabled")
  defer{UserDefaults.standard.set(oldLab,forKey:"labEnabled");UserDefaults.standard.set(oldEnabled,forKey:"labHostEnabled");UserDefaults.standard.set(oldPython,forKey:"labPythonPath");LabHostRuntime.shared.call("labCancel",args:[:],root:root,reply:{_,_ in})}
  let _:Any=try await withCheckedThrowingContinuation{c in LabRuntime.shared.call("labProjects",args:[:],root:root){v,e in if let e{c.resume(throwing:VaultError.message(e))}else{c.resume(returning:v ?? [:])}}}
  let store=try VaultStore(root:root,cache:qa.appendingPathComponent("cache"))
  let peer=DeviceSync(store:store,emit:{_ in},changed:{_ in});defer{peer.stop()}
  let config:[String:Any]=try await withCheckedThrowingContinuation{c in peer.call("syncCreate",args:[:]){v,e in if let e{c.resume(throwing:VaultError.message(e))}else{c.resume(returning:v as? [String:Any] ?? [:])}}}
  let pairing=qa.appendingPathComponent("ready.json")
  try JSONSerialization.data(withJSONObject:["code":config["code"]!,"root":root.path,"address":peer.labAddress() ?? ""]).write(to:pairing,options:.atomic)
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:pairing.path)
  for _ in 0..<240 {if FileManager.default.fileExists(atPath:qa.appendingPathComponent("done").path){return};try await Task.sleep(nanoseconds:1_000_000_000)}
  XCTFail("The iPad did not complete the paired-host acceptance run")
 }
}
#endif
