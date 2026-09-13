import XCTest
@testable import VaultCore
final class ModelLibraryTests:XCTestCase {
 func model()throws->URL {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  try Data(#"{"model_type":"llama","max_position_embeddings":8192,"torch_dtype":"bfloat16"}"#.utf8).write(to:root.appendingPathComponent("config.json"))
  try Data(#"{"chat_template":"test"}"#.utf8).write(to:root.appendingPathComponent("tokenizer_config.json"))
  try Data("{}".utf8).write(to:root.appendingPathComponent("tokenizer.json"));let header=Data(#"{"weight":{"dtype":"F32","shape":[8],"data_offsets":[0,32]}}"#.utf8);var count=UInt64(header.count).littleEndian;var weights=withUnsafeBytes(of:&count){Data($0)};weights.append(header);weights.append(Data(repeating:0,count:32));try weights.write(to:root.appendingPathComponent("model.safetensors"));return root
 }
 func testFolderValidationRejectsMissingShardsAndUnsupportedArchitecture()throws {
  let root=try model();defer{try? FileManager.default.removeItem(at:root)}
  let local=try ModelLibrary.inspect(root);XCTAssertEqual(local.architecture,"llama");XCTAssertEqual(local.context,8192)
  try Data(#"{"weight_map":{"a":"missing.safetensors"}}"#.utf8).write(to:root.appendingPathComponent("model.safetensors.index.json"));XCTAssertThrowsError(try ModelLibrary.inspect(root))
  try FileManager.default.removeItem(at:root.appendingPathComponent("model.safetensors.index.json"))
  try Data(#"{"model_type":"custom_remote_code"}"#.utf8).write(to:root.appendingPathComponent("config.json"));XCTAssertThrowsError(try ModelLibrary.inspect(root))
 }
 func testModelIDsAndLinksCannotEscapeTheLibrary()throws {
  for id in ["../outside","/tmp/model","..","model/child","model\\child"]{XCTAssertThrowsError(try ModelLibrary.selected(id))}
  let root=try model();defer{try? FileManager.default.removeItem(at:root)}
  try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("linked.json"),withDestinationURL:root.appendingPathComponent("config.json"));XCTAssertThrowsError(try ModelLibrary.inspect(root))
 }
}
