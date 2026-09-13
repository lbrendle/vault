import XCTest
import CryptoKit
@testable import VaultCore

final class StarterModelsTests: XCTestCase {
    private func fixture(_ mode: String = "range") throws -> (URL, StarterModel, Process, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = try ModelLibraryTests().model()
        defer { try? FileManager.default.removeItem(at: source) }
        for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try FileManager.default.copyItem(at: file, to: root.appendingPathComponent(file.lastPathComponent))
        }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).map { url -> [String: Any] in
            let data = try Data(contentsOf: url)
            return ["name": url.lastPathComponent, "bytes": data.count,
                    "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
        }
        let model: [String: Any] = ["id": "test", "name": "Synthetic test", "repository": "tests/model",
                                   "revision": String(repeating: "a", count: 40), "license": "Apache-2.0",
                                   "precision": "F32", "files": files]
        let decoded = try JSONDecoder().decode(StarterModel.self, from: JSONSerialization.data(withJSONObject: model))
        for name in ["Qwen-LICENSE.txt", "Qwen-NOTICE.txt"] { try Data("Synthetic fixture".utf8).write(to: root.appendingPathComponent(name)) }
        let server = Process(); server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        server.arguments = ["python3", "-u", "-c", #"""
import http.server, pathlib, sys
root, mode = pathlib.Path(sys.argv[1]), sys.argv[2]
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self, *args): pass
 def do_GET(self):
  name=self.path.rsplit('/',1)[-1]; data=(root/name).read_bytes(); offset=0
  if self.headers.get('Range') and mode!='ignore':
   offset=int(self.headers['Range'].split('=')[1].split('-')[0]); self.send_response(206)
   self.send_header('Content-Range',f'bytes {offset}-{len(data)-1}/{len(data)}')
   (root/'range-observed').write_text(str(offset))
  else: self.send_response(200)
  if mode=='corrupt': data=b'X'*len(data)
  self.send_header('Content-Length',str(len(data)-offset)); self.end_headers(); self.wfile.write(data[offset:])
server=http.server.HTTPServer(('127.0.0.1',0),Handler)
print(server.server_port,flush=True);server.serve_forever()
"""#, root.path, mode]
        let output = Pipe(); server.standardOutput = output; server.standardError = FileHandle.nullDevice
        try server.run()
        var line = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty, byte != Data([10]) { line.append(byte) }
        let port = try XCTUnwrap(Int(String(decoding: line, as: UTF8.self)))
        return (root, decoded, server, URL(string: "http://127.0.0.1:\(port)")!)
    }
    private func exercise(_ mode: String) async throws {
        let (root, model, server, url) = try fixture(mode)
        defer { server.terminate(); try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("library")
        let staging = destination.appendingPathComponent(".download-model-\(model.revision)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let weights = try Data(contentsOf: root.appendingPathComponent("model.safetensors"))
        try weights.prefix(12).write(to: staging.appendingPathComponent("model.safetensors"))
        let result = try await StarterModelInstaller.install(model, root: destination, notices: root, baseURL: url) { _,_,_ in }
        XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent("model.safetensors")), weights)
        XCTAssertEqual(try ModelLibrary.inspect(result).name, "Synthetic test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.appendingPathComponent("LICENSE").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        if mode == "range" { XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("range-observed")), "12") }
        do {
            _ = try await StarterModelInstaller.install(model, root: destination, notices: root, baseURL: url) { _,_,_ in }
            XCTFail("Must preserve an already installed folder")
        } catch { XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent("model.safetensors")), weights) }
    }
    func testResumesAndAtomicallyInstallsVerifiedModel() async throws { try await exercise("range") }
    func testRestartsWhenServerIgnoresRange() async throws { try await exercise("ignore") }
    func testCorruptedDownloadNeverAppearsInLibrary() async throws {
        let (root, model, server, url) = try fixture("corrupt")
        defer { server.terminate(); try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("library")
        do {
            _ = try await StarterModelInstaller.install(model, root: destination, notices: root, baseURL: url) { _,_,_ in }
            XCTFail("Corrupt model must fail verification")
        } catch { XCTAssertTrue(error.localizedDescription.contains("checksum")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("model").path))
    }
}
