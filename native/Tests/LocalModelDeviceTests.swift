import XCTest
import Foundation
import os
import VaultCore

private final class RecordedEvents: @unchecked Sendable {
    private let lock=NSLock()
    private var events=[[String:Any]]()
    func append(_ event:[String:Any]) {lock.lock();events.append(event);lock.unlock()}
    func snapshot()->[[String:Any]] {lock.lock();defer{lock.unlock()};return events}
}

final class LocalModelDeviceTests:XCTestCase {
    @MainActor private func verify(_ id:String)async throws {
        guard FileManager.default.fileExists(atPath:ModelLibrary.root.appendingPathComponent(id).path) else {throw XCTSkip("Install the optional model fixture on this device first.")}
        let available=LocalModel.availableMemory,events=RecordedEvents(),done=expectation(description:"Local model unloaded")
        let runner=LocalModel {event in events.append(event);if event["event"] as? String=="unloaded"{done.fulfill()}}
        // Synthetic evidence only. This test never reads the user's documents or chat history.
        let prompt="Use only this fictional evidence. Study A enrolled 80 people and 48 improved; it had no control group. Study B randomized 120 people: 36 of 60 treated people improved, versus 30 of 60 controls. In three sentences, give both treatment improvement rates, the absolute treatment-control difference in Study B, and whether Study A alone establishes causation."
        runner.call(["model_id":id,"history":[["role":"user","content":prompt]],"thinking":"off","max_tokens":256,"context_tokens":2048,"temperature":0.0]) {_,error in
            if let error {events.append(["event":"error","data":["message":error]]);done.fulfill()}
        }
        await fulfillment(of:[done],timeout:180)
        runner.stop()
        let recorded=events.snapshot(),answer=recorded.filter{$0["event"] as? String=="delta"}.compactMap{($0["data"] as? [String:Any])?["text"] as? String}.joined()
        let errors=recorded.filter{$0["event"] as? String=="error"}
        let receipt:[String:Any]=["model":id,"prompt":prompt,"answer":answer,"availableMemoryBefore":available,"events":recorded,"device":"physical Apple device","date":ISO8601DateFormatter().string(from:Date())]
        let output=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("model-test-"+id+".json")
        try JSONSerialization.data(withJSONObject:receipt,options:[.prettyPrinted,.sortedKeys]).write(to:output,options:.atomic)
        XCTAssertTrue(errors.isEmpty,"Local generation failed: \(errors)")
        XCTAssertTrue(recorded.contains{$0["event"] as? String=="complete"},"Generation must finish")
        XCTAssertTrue(answer.contains("60")&&answer.contains("10"),"Check the supplied rates and difference: \(answer)")
        XCTAssertFalse(answer.contains("<turn|>"),"End-of-turn tokens must terminate generation")
    }
    @MainActor func testQwen2BEvidenceReasoning()async throws {try await verify("Qwen3.5-2B-4bit")}
    @MainActor func testGemma4EvidenceReasoning()async throws {try await verify("gemma-4-e4b-it-4bit")}
    @MainActor func testQwen4BEvidenceReasoning()async throws {try await verify("Qwen3.5-4B-4bit")}
}
