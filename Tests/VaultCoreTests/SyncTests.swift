import XCTest
import Network
@testable import VaultCore
final class SyncTests:XCTestCase {
 func testCachedScanPreservesChangesAndRejectsAReplacedSymlinkAncestor()throws {
  for i in 0..<2000 {try write(a,"Library/Notes/Item \(i).md","Original \(i)")}
  try a.scan();let before=try a.journalHead(),began=Date()
  a.invalidate();try a.scan()
  print("Cached sync scan: 2000 documents in \(Date().timeIntervalSince(began)) seconds")
  XCTAssertEqual(try a.journalHead().sequence,before.sequence)
  try write(a,"Library/Notes/Item 9.md","A changed document")
  try FileManager.default.removeItem(at:a.store.safeURL("Library/Notes/Item 10.md"))
  a.invalidate();try a.scan()
  let changed=try a.journalChanges(after:before.sequence,through:a.journalHead().sequence)
  XCTAssertEqual(Set(changed.entries.map(\.path)),Set(["Library/Notes/Item 9.md","Library/Notes/Item 10.md"]))
  let directory=a.store.root.appendingPathComponent("Library")
  try FileManager.default.moveItem(at:directory,to:base.appendingPathComponent("Moved library"))
  try FileManager.default.createSymbolicLink(at:directory,withDestinationURL:b.store.root)
  try write(b,"Notes/Item 9.md","Outside the vault")
  a.invalidate();XCTAssertThrowsError(try a.scan())
  XCTAssertNotEqual(try a.entry("Library/Notes/Item 9.md")?.hash,VaultStore.fingerprint(Data("Outside the vault".utf8)))
 }
 func testConnectionUsesReachableRouteAndCancelsTheStalledRoute()async throws {
  let secret=Data(repeating:39,count:32)
  let(listener,port)=try await listening(secret:secret,server:PeerTransfer(catalog:a));defer{listener.cancel()}
  // A plain TCP listener accepts but never answers the TLS handshake.
  let stalled=try NWListener(using:.tcp,on:.any),queue=DispatchQueue(label:"test.stalled.route")
  var sockets=[NWConnection]()
  stalled.newConnectionHandler={connection in sockets.append(connection);connection.start(queue:queue)}
  let stalledPort=try await withCheckedThrowingContinuation{(c:CheckedContinuation<NWEndpoint.Port,Error>) in
   var pending=true;stalled.stateUpdateHandler={state in guard pending else{return};if case .ready=state{pending=false;c.resume(returning:stalled.port!)}else if case .failed(let e)=state{pending=false;c.resume(throwing:e)}};stalled.start(queue:queue)
  }
  defer{stalled.cancel();queue.sync{sockets.forEach{$0.cancel()}}}
  let began=Date()
  let channel=try await PeerChannel.connect(to:[.hostPort(host:"127.0.0.1",port:stalledPort),.hostPort(host:"127.0.0.1",port:port)],secret:secret)
  defer{channel.close()}
  XCTAssertLessThan(Date().timeIntervalSince(began),5,"A stale route must not hold up a reachable peer")
  let response=try await channel.request("hello")
  XCTAssertEqual(response["device"] as? String,"A")
 }
 func testBonjourCollisionSuffixNeverCreatesASelfPeer() {
  let group="0123456789abcdef0123456789abcdef",local="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",remote="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",prefix=String(group.prefix(12))+"-"
  for suffix in [""," (2)"," (12)"] {
   XCTAssertNil(PeerIdentity.device(in:prefix+local+suffix,group:group,excluding:local))
   XCTAssertEqual(PeerIdentity.device(in:prefix+remote+suffix,group:group,excluding:local),remote)
  }
  for name in [prefix+"short",prefix+remote+"-unexpected","other-"+remote] {XCTAssertNil(PeerIdentity.device(in:name,group:group,excluding:local))}
 }
 func testAuthenticatedSelfConnectionIsRejectedBeforeSync()async throws {
  let secret=Data(repeating:39,count:32),transfer=PeerTransfer(catalog:a)
  let(listener,port)=try await listening(secret:secret,server:transfer);defer{listener.cancel()}
  let channel=PeerChannel(NWConnection(host:"127.0.0.1",port:port,using:PeerTLS.parameters(secret:secret)));defer{channel.close()}
  try await channel.ready()
  do {try await transfer.synchronize(channel);XCTFail("Self sync must not run")}catch {XCTAssertTrue(error.localizedDescription.contains("same device"))}
 }
 var base:URL!,a:SyncCatalog!,b:SyncCatalog!
 override func setUpWithError()throws {
  base=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  for name in ["a","b"]{try FileManager.default.createDirectory(at:base.appendingPathComponent(name),withIntermediateDirectories:true)}
  a=try SyncCatalog(store:VaultStore(root:base.appendingPathComponent("a"),cache:base.appendingPathComponent("ac")),device:"A")
  b=try SyncCatalog(store:VaultStore(root:base.appendingPathComponent("b"),cache:base.appendingPathComponent("bc")),device:"B")
 }
 override func tearDownWithError()throws{a=nil;b=nil;try FileManager.default.removeItem(at:base)}
 func write(_ catalog:SyncCatalog,_ path:String,_ text:String)throws{let p=catalog.store.root.appendingPathComponent(path);try FileManager.default.createDirectory(at:p.deletingLastPathComponent(),withIntermediateDirectories:true);try Data(text.utf8).write(to:p,options:.atomic)}
 func copy(_ source:SyncCatalog,_ destination:SyncCatalog,_ path:String)throws{let e=try XCTUnwrap(source.entry(path));if try destination.needs(e){let temp=try destination.staging(e);try? FileManager.default.removeItem(at:temp);try FileManager.default.copyItem(at:source.store.safeURL(path),to:temp);try destination.apply(e,temporary:temp)}}
 func testOfflineConflictsConvergeWithoutLosingEitherEdit()throws{
  try write(a,"Note.md","original");a.invalidate();try a.scan();try copy(a,b,"Note.md")
  try write(a,"Note.md","Mac edit");try write(b,"Note.md","iPad edit");a.invalidate();try a.scan();b.invalidate();try b.scan()
  try copy(a,b,"Note.md");try copy(b,a,"Note.md")
  for e in try b.manifest() where !e.deleted {try copy(b,a,e.path)}
  for e in try a.manifest() where !e.deleted {try copy(a,b,e.path)}
  XCTAssertEqual(try a.store.read("Note.md")["content"] as? String,try b.store.read("Note.md")["content"] as? String)
  for c in [a!,b!] {let entries=try c.manifest();let contents=try entries.filter{!$0.deleted}.map{try String(contentsOf:c.store.safeURL($0.path),encoding:.utf8)};XCTAssertEqual(Set(contents),Set(["Mac edit","iPad edit"]))}
  XCTAssertEqual(try a.entry("Note.md")?.clock,try b.entry("Note.md")?.clock)
 }
 func testTombstonesAndEditDeleteConflict()throws {
  try write(a,"Note.md","original");a.invalidate();try a.scan();try copy(a,b,"Note.md")
  try FileManager.default.removeItem(at:a.store.safeURL("Note.md"));a.invalidate();try a.scan()
  try write(b,"Note.md","new evidence while offline");b.invalidate();try b.scan()
  let deleted=try XCTUnwrap(a.entry("Note.md"));XCTAssertFalse(try b.needs(deleted));try copy(b,a,"Note.md")
  XCTAssertEqual(try a.store.read("Note.md")["content"] as? String,"new evidence while offline")
  try FileManager.default.removeItem(at:a.store.safeURL("Note.md"));a.invalidate();try a.scan();XCTAssertFalse(try b.needs(XCTUnwrap(a.entry("Note.md"))))
  XCTAssertFalse(FileManager.default.fileExists(atPath:try b.store.safeURL("Note.md").path));XCTAssertFalse(try b.store.recovery("Note.md").isEmpty)
 }
 func testExcludedPathsAndChecksumFailureNeverOverwrite()throws {
  try write(a,"node_modules/secret.md","private");try write(a,".git/secret.md","private");try write(a,"Note.md","original");a.invalidate();try a.scan();XCTAssertEqual(try a.manifest().map(\.path),["Note.md"])
  try copy(a,b,"Note.md");try write(a,"Note.md","updated");a.invalidate();try a.scan();let e=try XCTUnwrap(a.entry("Note.md")),temp=try b.staging(e);try Data("corrupted".utf8).write(to:temp)
  XCTAssertThrowsError(try b.apply(e,temporary:temp));XCTAssertEqual(try b.store.read("Note.md")["content"] as? String,"original")
  var invalid=e;invalid.path="../outside.md";XCTAssertFalse(try b.needs(invalid));XCTAssertThrowsError(try b.apply(invalid,temporary:temp))
 }
 func testSharedConversationBranchesAndBookmarkRemovalSurviveStaleSaves()throws {
  try a.store.saveState(["chats":[["id":"c","updated":1,"messages":[["role":"user","content":"original"]]]],"bookmarks":["Note.md"]])
  let stale=try a.store.state()
  try a.store.mergeSharedState(["chats":[["id":"c","updated":2,"messages":[["role":"user","content":"different offline edit"]]]],"bookmarkChanges":["Note.md":["present":false,"modified":2]]])
  try a.store.saveState(stale)
  let value=try a.store.state(),chats=value["chats"] as? [[String:Any]] ?? []
  XCTAssertEqual(chats.count,2);XCTAssertEqual(value["bookmarks"] as? [String],[])
  XCTAssertTrue(chats.contains{($0["messages"] as? [[String:Any]])?.first?["content"] as? String=="original"})
  XCTAssertTrue(chats.contains{($0["messages"] as? [[String:Any]])?.first?["content"] as? String=="different offline edit"})
 }
 func listening(secret:Data,server:PeerTransfer,stall:Bool=false)async throws->(NWListener,NWEndpoint.Port){
  let listener=try NWListener(using:PeerTLS.parameters(secret:secret),on:.any),queue=DispatchQueue(label:"test.sync.listener")
  listener.newConnectionHandler={connection in let ch=PeerChannel(connection);Task{do{try await ch.ready();if stall {_ = try await ch.receive();try await Task.sleep(nanoseconds:500_000_000);ch.close()}else{await server.serve(ch)}}catch{ch.close()}}}
  let port=try await withCheckedThrowingContinuation{(c:CheckedContinuation<NWEndpoint.Port,Error>)in var pending=true;listener.stateUpdateHandler={s in guard pending else{return};if case .ready=s{pending=false;c.resume(returning:listener.port!)}else if case .failed(let e)=s{pending=false;c.resume(throwing:e)}};listener.start(queue:queue)}
  return(listener,port)
 }
 func testEncryptedTransferResumesLargeFileAndSyncsBothWays()async throws {
  let data=Data((0..<(1024*1024+17)).map{UInt8($0%251)})
  try data.write(to:a.store.root.appendingPathComponent("Paper.pdf"));try write(a,"Mac.md","from mac");try write(a,"Empty.md","");try write(b,"iPad.md","from iPad")
  a.invalidate();try a.scan();b.invalidate();try b.scan();let e=try XCTUnwrap(a.entry("Paper.pdf"));try data.prefix(262144).write(to:b.staging(e))
  try a.store.saveState(["chats":[["id":"chat-a","title":"Research","updated":1,"messages":[["role":"user","content":String(repeating:"A research excerpt. ",count:40000)]]]],"bookmarks":["Mac.md"]])
  let secret=Data(repeating:39,count:32),server=PeerTransfer(catalog:a),client=PeerTransfer(catalog:b)
  let(listener,port)=try await listening(secret:secret,server:server);defer{listener.cancel()}
  let channel=PeerChannel(NWConnection(host:"127.0.0.1",port:port,using:PeerTLS.parameters(secret:secret)));defer{channel.close()};try await channel.ready();try await client.synchronize(channel)
  XCTAssertEqual(try Data(contentsOf:b.store.safeURL("Paper.pdf")),data)
  XCTAssertEqual(try Data(contentsOf:b.store.safeURL("Empty.md")).count,0)
  XCTAssertEqual(try a.store.read("iPad.md")["content"] as? String,"from iPad")
  XCTAssertEqual((try b.store.state()["chats"] as? [[String:Any]])?.first?["id"] as? String,"chat-a")
 }
 func testSmallBatchRejectsCorruptionBeforeApplyingAnyFile()throws {
  try write(a,"One.md","one");try write(a,"Two.md","two");try a.scan()
  let server=PeerTransfer(catalog:a),client=PeerTransfer(catalog:b)
  let entries=try a.manifest().map{try JSONSerialization.jsonObject(with:JSONEncoder().encode($0)) as! [String:Any]}
  let payload=try server.respond(command:"getSmallBatch",args:["entries":entries])
  var files=payload["files"] as! [[String:Any]]
  files[1]["data"]=Data("bad".utf8).base64EncodedString()
  XCTAssertThrowsError(try client.respond(command:"putSmallBatch",args:["files":files]))
  XCTAssertFalse(FileManager.default.fileExists(atPath:b.store.root.appendingPathComponent("One.md").path))
  _ = try client.respond(command:"putSmallBatch",args:payload)
  XCTAssertEqual(try b.store.read("Two.md")["content"] as? String,"two")
  XCTAssertThrowsError(try server.respond(command:"getSmallBatch",args:["entries":Array(repeating:entries[0],count:9)]))
 }
 func testRepeatedDocumentUsesVerifiedLocalCopy()throws {
  try write(a,"Papers/Original.md","same research");try a.scan();try copy(a,b,"Papers/Original.md")
  try write(a,"Reading List/Copy.md","same research");try a.refresh(["Reading List/Copy.md"])
  XCTAssertFalse(try b.needs(XCTUnwrap(a.entry("Reading List/Copy.md"))))
  XCTAssertEqual(try b.store.read("Reading List/Copy.md")["content"] as? String,"same research")
  try write(b,"Papers/Original.md","independent edit")
  XCTAssertEqual(try b.store.read("Reading List/Copy.md")["content"] as? String,"same research")
 }
 func testManualSyncDiscoversExternalFilesDespiteScanThrottle()throws {
  try write(a,"First.md","existing");try a.scan();try write(a,"Added in another app.md","external edit")
  let server=PeerTransfer(catalog:a)
  _ = try server.respond(command:"manifest",args:[:]);XCTAssertNil(try a.entry("Added in another app.md"))
  _ = try server.respond(command:"manifest",args:["force":true]);XCTAssertNotNil(try a.entry("Added in another app.md"))
 }
 func testWrongPairingKeyCannotEstablishAConnection()async throws {
  let(listener,port)=try await listening(secret:Data(repeating:1,count:32),server:PeerTransfer(catalog:a));defer{listener.cancel()}
  let channel=PeerChannel(NWConnection(host:"127.0.0.1",port:port,using:PeerTLS.parameters(secret:Data(repeating:2,count:32))));defer{channel.close()}
  do{try await channel.ready();XCTFail("An unpaired peer connected")}catch{}
 }
 func testStalledPeerRequestTimesOut()async throws {
  let secret=Data(repeating:39,count:32)
  let(listener,port)=try await listening(secret:secret,server:PeerTransfer(catalog:a),stall:true);defer{listener.cancel()}
  let channel=PeerChannel(NWConnection(host:"127.0.0.1",port:port,using:PeerTLS.parameters(secret:secret)));defer{channel.close()}
  try await channel.ready()
  do {_ = try await channel.request("hello",timeout:0.1);XCTFail("Stalled request did not stop")}catch {XCTAssertTrue(error.localizedDescription.contains("stopped responding"))}
 }
 func testDurableJournalTracksOnlyChangedContentAndTombstones()throws {
  for i in 0..<400 {try write(a,"Note \(i).md","original \(i)")};try a.scan()
  let head=try a.journalHead();XCTAssertEqual(head.sequence,400)
  a.invalidate();try a.scan();XCTAssertEqual(try a.journalHead().sequence,head.sequence)
  try write(a,"Note 2.md","edited outside the app");try a.refresh(["Note 2.md"])
  try FileManager.default.removeItem(at:a.store.safeURL("Note 3.md"));try a.refresh(["Note 3.md"])
  let page=try a.journalChanges(after:head.sequence,through:a.journalHead().sequence)
  XCTAssertEqual(page.entries.map(\.path),["Note 2.md","Note 3.md"]);XCTAssertTrue(page.entries[1].deleted)
  try a.acknowledge("B",epoch:head.epoch,sequence:page.cursor)
  let reopened=try SyncCatalog(store:a.store,device:"A")
  XCTAssertEqual(try reopened.peerCursor("B",epoch:head.epoch),page.cursor)
  XCTAssertEqual(try reopened.peerCursor("B",epoch:UUID().uuidString),0)
  // A second edit after a captured high-water mark belongs to the next pass.
  let captured=try a.journalHead();try write(a,"Note 2.md","edited again");try a.refresh(["Note 2.md"])
  XCTAssertEqual(try a.journalChanges(after:head.sequence,through:captured.sequence).entries.map(\.path),["Note 3.md"])
  XCTAssertEqual(try a.journalChanges(after:captured.sequence,through:a.journalHead().sequence).entries.map(\.path),["Note 2.md"])
 }
 func testDeltaReconnectSyncsExternalEditsBothWaysAndKeepsConflicts()async throws {
  for i in 0..<300 {try write(a,"Note \(i).md","original \(i)")};try a.scan()
  let secret=Data(repeating:39,count:32),server=PeerTransfer(catalog:a),client=PeerTransfer(catalog:b)
  let(listener,port)=try await listening(secret:secret,server:server);defer{listener.cancel()}
  func pass()async throws {
   let channel=PeerChannel(NWConnection(host:"127.0.0.1",port:port,using:PeerTLS.parameters(secret:secret)));defer{channel.close()}
   try await channel.ready();try await client.synchronize(channel,forceScan:true)
  }
  try await pass()
  let baseline=try a.journalHead()
  XCTAssertEqual(try b.peerCursor("A",epoch:baseline.epoch),baseline.sequence)
  try write(a,"Note 2.md","Mac edit");try write(b,"New iPad.md","iPad edit");try await pass()
  XCTAssertEqual(try b.store.read("Note 2.md")["content"] as? String,"Mac edit")
  XCTAssertEqual(try a.store.read("New iPad.md")["content"] as? String,"iPad edit")
  XCTAssertEqual(Set(try a.journalChanges(after:baseline.sequence,through:a.journalHead().sequence).entries.map(\.path)),Set(["Note 2.md","New iPad.md"]))
  try write(a,"Note 2.md","offline Mac");try write(b,"Note 2.md","offline iPad");try await pass();try await pass()
  for c in [a!,b!] {
   let rows=try c.db.execute("SELECT path FROM entries WHERE path LIKE 'Note 2%' AND deleted=0")
   let contents=try rows.map{try String(contentsOf:c.store.safeURL($0["path"] as! String),encoding:.utf8)}
   XCTAssertTrue(contents.contains("offline Mac"));XCTAssertTrue(contents.contains("offline iPad"))
  }
 }
}
