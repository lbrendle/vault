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
  // All-FF bytes become base64 slashes; the default JSON escaping used to
  // overflow the frame limit even though the binary block was within bounds.
  let data=Data(repeating:255,count:2*1024*1024+17)
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
 func testChatMergeKeepsTheLongerConversationAndTheNewerTitle()throws {
  func turn(_ role:String,_ text:String)->[String:Any]{["role":role,"content":text]}
  let four=[turn("user","q1"),turn("assistant","a1"),turn("user","q2"),turn("assistant","a2")],six=four+[turn("user","q3"),turn("assistant","a3")]
  let continued:[String:Any]=["id":"c","title":"Research","updated":150.0,"messages":six],renamed:[String:Any]=["id":"c","title":"Renamed","archived":true,"updated":200.0,"messages":four]
  // One device continued the conversation offline; the other renamed and archived its older copy afterwards.
  try a.store.saveState(["chats":[continued]]);try a.store.mergeSharedState(["chats":[renamed]])
  try b.store.saveState(["chats":[renamed]]);try b.store.mergeSharedState(["chats":[continued]])
  for store in [a.store,b.store] {
   let chats=try store.state()["chats"] as? [[String:Any]] ?? [];XCTAssertEqual(chats.count,1)
   XCTAssertEqual((chats.first?["messages"] as? [[String:Any]])?.compactMap{$0["content"] as? String},["q1","a1","q2","a2","q3","a3"])
   XCTAssertEqual(chats.first?["title"] as? String,"Renamed");XCTAssertEqual(chats.first?["archived"] as? Bool,true);XCTAssertEqual(chats.first?["updated"] as? Double,200)
  }
 }
 func testOversizedTransferOffsetsAreRejectedWithoutOverflow()throws {
  try write(a,"Paper.pdf","contents");try a.scan()
  let offer=try JSONSerialization.jsonObject(with:JSONEncoder().encode(XCTUnwrap(a.entry("Paper.pdf")))) as! [String:Any],client=PeerTransfer(catalog:b),block=Data("c".utf8).base64EncodedString()
  XCTAssertThrowsError(try client.respond(command:"put",args:["entry":offer,"offset":Int.max,"data":block]))
  let id=try XCTUnwrap(client.respond(command:"stateBegin",args:[:])["id"] as? String)
  XCTAssertThrowsError(try client.respond(command:"statePut",args:["id":id,"offset":Int.max,"data":block]))
  // Blocks that fit are still accepted.
  XCTAssertEqual(try client.respond(command:"put",args:["entry":offer,"offset":0,"data":block])["offset"] as? Int,1)
  XCTAssertEqual(try client.respond(command:"statePut",args:["id":id,"offset":0,"data":block])["ok"] as? Bool,true)
 }
 func testMissingVaultRootIsNeverRecreatedAndNothingIsTombstoned()throws {
  try write(a,"Notes/One.md","one");try write(a,"Two.md","two");try write(b,"Peer.md","from peer");a.invalidate();try a.scan();b.invalidate();try b.scan()
  let root=a.store.root,renamed=base.appendingPathComponent("a renamed"),offered=try XCTUnwrap(b.entry("Peer.md")),transfer=PeerTransfer(catalog:a)
  let received=base.appendingPathComponent("received.partial");try Data("from peer".utf8).write(to:received)
  // The folder is renamed in Finder while the app still holds the old path.
  try FileManager.default.moveItem(at:root,to:renamed)
  XCTAssertThrowsError(try a.store.saveState(["bookmarks":["Two.md"]]))
  XCTAssertThrowsError(try a.store.mergeSharedState(["chats":[["id":"c","updated":1,"messages":[]]]]))
  XCTAssertThrowsError(try a.store.saveRules(a.store.rules))
  XCTAssertThrowsError(try a.store.save("Fresh/Note.md",content:"new",revision:nil))
  XCTAssertThrowsError(try a.store.folder("Fresh"))
  XCTAssertThrowsError(try a.staging(offered))
  XCTAssertThrowsError(try a.apply(offered,temporary:received))
  XCTAssertThrowsError(try transfer.respond(command:"stateBegin",args:[:]))
  XCTAssertThrowsError(try transfer.respond(command:"stateExport",args:[:]))
  XCTAssertFalse(FileManager.default.fileExists(atPath:root.path),"The vault folder must not reappear empty")
  a.invalidate();XCTAssertThrowsError(try a.scan())
  XCTAssertTrue(try a.manifest().allSatisfy{!$0.deleted})
  // Back in place, the same catalog continues without having recorded a deletion.
  try FileManager.default.moveItem(at:renamed,to:root);a.invalidate();try a.scan()
  XCTAssertEqual(try a.manifest().filter{!$0.deleted}.map(\.path),["Notes/One.md","Two.md"])
 }
 func testEqualClocksWithDifferentContentAreKeptAsConflictsInBothDirections()throws {
  try write(a,"Note.md","original");try write(a,"Gone.md","original");a.invalidate();try a.scan();try copy(a,b,"Note.md");try copy(a,b,"Gone.md")
  try FileManager.default.removeItem(at:a.store.safeURL("Gone.md"));try a.refresh(["Gone.md"]);XCTAssertFalse(try b.needs(XCTUnwrap(a.entry("Gone.md"))))
  // A second catalog under the same replica ID (a device set up from another's backup) counts
  // from one again, so its clocks equal the ones the peer still holds.
  let cache=base.appendingPathComponent("ac-reset"),seeded=try Database(cache.appendingPathComponent("sync.sqlite"))
  try seeded.execute("CREATE TABLE replica(id INTEGER PRIMARY KEY,value TEXT NOT NULL)");try seeded.execute("INSERT INTO replica VALUES(1,?)",[a.replica])
  let reset=try SyncCatalog(store:VaultStore(root:a.store.root,cache:cache),device:"A");XCTAssertEqual(reset.replica,a.replica)
  try write(reset,"Note.md","edited after the catalog was lost");try write(reset,"Gone.md","written again");try reset.scan()
  try write(reset,"Gone.md","written again, then edited");try reset.refresh(["Gone.md"])
  XCTAssertEqual(try reset.entry("Note.md")?.clock,try b.entry("Note.md")?.clock);XCTAssertEqual(try reset.entry("Gone.md")?.clock,try b.entry("Gone.md")?.clock)
  XCTAssertTrue(try b.needs(XCTUnwrap(reset.entry("Note.md"))));XCTAssertTrue(try reset.needs(XCTUnwrap(b.entry("Note.md"))))
  // A deletion and a live document with equal clocks keep the live document.
  XCTAssertFalse(try reset.needs(XCTUnwrap(b.entry("Gone.md"))));XCTAssertTrue(try b.needs(XCTUnwrap(reset.entry("Gone.md"))))
  try copy(reset,b,"Note.md");try copy(b,reset,"Note.md")
  for e in try b.manifest() where !e.deleted {try copy(b,reset,e.path)}
  for e in try reset.manifest() where !e.deleted {try copy(reset,b,e.path)}
  XCTAssertEqual(try reset.store.read("Note.md")["content"] as? String,try b.store.read("Note.md")["content"] as? String)
  for c in [reset,b!] {
   let notes=try c.manifest().filter{!$0.deleted && $0.path.hasPrefix("Note")}.map{try String(contentsOf:c.store.safeURL($0.path),encoding:.utf8)}
   XCTAssertEqual(notes.count,2);XCTAssertEqual(Set(notes),Set(["original","edited after the catalog was lost"]))
   XCTAssertEqual(try c.store.read("Gone.md")["content"] as? String,"written again, then edited")
  }
 }
 func testSyncedReplacementKeepsFinderTagsAndCreationDate()throws {
  try write(a,"Note.md","original");try a.scan();try copy(a,b,"Note.md")
  let url=try b.store.safeURL("Note.md"),tags=Data("<plist><array><string>Blue</string></array></plist>".utf8),born=Date(timeIntervalSince1970:1_600_000_000)
  setAttribute(url,"com.apple.metadata:_kMDItemUserTags",tags);try FileManager.default.setAttributes([.creationDate:born],ofItemAtPath:url.path)
  try write(a,"Note.md","edited on the other device");try a.refresh(["Note.md"]);try copy(a,b,"Note.md")
  XCTAssertEqual(try b.store.read("Note.md")["content"] as? String,"edited on the other device")
  XCTAssertEqual(attribute(url,"com.apple.metadata:_kMDItemUserTags"),tags);XCTAssertEqual(try FileManager.default.attributesOfItem(atPath:url.path)[.creationDate] as? Date,born)
  XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:b.store.root.path).sorted(),[".archii-vault","Note.md"],"Nothing is left beside the document")
  XCTAssertEqual(try b.entry("Note.md"),try a.entry("Note.md"))
 }
 func testInterruptedTransferFilesAreRemovedAfterAWeek()throws {
  let incoming=a.store.metadata.appendingPathComponent("sync/incoming"),states=a.store.metadata.appendingPathComponent("sync/state-transfers")
  for folder in [incoming,states] {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}
  func file(_ url:URL,daysOld:Double)throws {try Data("left behind".utf8).write(to:url);try FileManager.default.setAttributes([.modificationDate:Date().addingTimeInterval(-daysOld*86400)],ofItemAtPath:url.path)}
  try file(incoming.appendingPathComponent("abandoned.partial"),daysOld:8);try file(incoming.appendingPathComponent("resuming.partial"),daysOld:6);try file(incoming.appendingPathComponent("other.dat"),daysOld:30)
  try file(states.appendingPathComponent("abandoned.json"),daysOld:8);try file(states.appendingPathComponent("recent.json"),daysOld:1);try file(states.appendingPathComponent("other.txt"),daysOld:30)
  a.invalidate();try a.scan()
  XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:incoming.path).sorted(),["other.dat","resuming.partial"])
  XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:states.path).sorted(),["other.txt","recent.json"])
 }
 func testOneDocumentTheOtherDeviceDeclinesDoesNotStopTheRestOfTheSendPhase()async throws {
  // This device (b) starts the pass and has everything to send. The paper that the other device has no
  // room for is the first change in this journal, ahead of more than a page of notes.
  try Data(repeating:7,count:2*1024*1024).write(to:b.store.root.appendingPathComponent("Paper.pdf"));try b.scan()
  for i in 0..<150 {try write(b,"Note \(i).md","note \(i)")};try write(b,"Figure.pdf",String(repeating:"f",count:40*1024));b.invalidate();try b.scan()
  try write(a,"From the Mac.md","written on the other device")
  let secret=Data(repeating:39,count:32),server=PeerTransfer(catalog:a),client=PeerTransfer(catalog:b)
  let(listener,port)=try await listening(secret:secret,server:server);defer{listener.cancel()}
  func pass()async throws {
   let channel=PeerChannel(NWConnection(host:"127.0.0.1",port:port,using:PeerTLS.parameters(secret:secret)));defer{channel.close()}
   try await channel.ready();try await client.synchronize(channel,forceScan:true)
  }
  // The other device has room for everything except the 2 MiB paper: a transfer needs its size plus a 64 MiB reserve.
  a.freeSpace={_ in 65*1024*1024}
  do {try await pass();XCTFail("The declined document must be reported")}catch {
   XCTAssertTrue(error.localizedDescription.contains("could not accept Paper.pdf"),error.localizedDescription)
   XCTAssertTrue(error.localizedDescription.contains("Not enough free space"),error.localizedDescription)
  }
  XCTAssertFalse(FileManager.default.fileExists(atPath:a.store.root.appendingPathComponent("Paper.pdf").path))
  XCTAssertEqual(try a.manifest(limit:256).filter{!$0.deleted && $0.path.hasPrefix("Note ")}.count,150,"Documents after the declined one, on this page and the next, are still sent")
  XCTAssertEqual(try a.store.read("Figure.pdf")["size"] as? Int,40*1024)
  XCTAssertEqual(try b.store.read("From the Mac.md")["content"] as? String,"written on the other device","Receiving is unaffected")
  XCTAssertEqual(try a.peerCursor("B",epoch:b.journalHead().epoch),0,"Nothing from the declined document onwards is acknowledged")
  // With room again the next pass offers the paper once more, and the cursor catches up.
  a.freeSpace={_ in Int64.max};try await pass()
  XCTAssertEqual(try Data(contentsOf:a.store.safeURL("Paper.pdf")).count,2*1024*1024)
  XCTAssertEqual(try a.peerCursor("B",epoch:b.journalHead().epoch),try b.journalHead().sequence)
  // A path the other device has to refuse (a folder that is a symbolic link there) makes it decline the
  // whole page of offers. The page is offered again one document at a time, and only that document is put off.
  try FileManager.default.createSymbolicLink(at:a.store.root.appendingPathComponent("Linked"),withDestinationURL:base)
  try write(b,"Linked/Inside.md","behind a link on the other device");try b.refresh(["Linked/Inside.md"]);try write(b,"Zebra.md","after it");try b.refresh(["Zebra.md"])
  do {try await pass();XCTFail("The refused document must be reported")}catch {
   XCTAssertTrue(error.localizedDescription.contains("could not accept Linked/Inside.md"),error.localizedDescription)
   XCTAssertTrue(error.localizedDescription.contains("Symbolic links"),error.localizedDescription)
  }
  XCTAssertEqual(try a.store.read("Zebra.md")["content"] as? String,"after it")
  // A document that changed on this device since the catalog last looked is put off too, and what
  // follows it is still sent. With the link gone, the document refused earlier now arrives as well.
  try FileManager.default.removeItem(at:a.store.root.appendingPathComponent("Linked"))
  try write(b,"Draft.md","first");try b.refresh(["Draft.md"]);try write(b,"Later.md","sent anyway");try b.refresh(["Later.md"])
  try "second, longer".write(to:b.store.root.appendingPathComponent("Draft.md"),atomically:true,encoding:.utf8)
  do {
   let channel=PeerChannel(NWConnection(host:"127.0.0.1",port:port,using:PeerTLS.parameters(secret:secret)));defer{channel.close()}
   try await channel.ready();try await client.synchronize(channel);XCTFail("The document that could not be sent must be reported")
  }catch {XCTAssertTrue(error.localizedDescription.contains("Could not send Draft.md"),error.localizedDescription)}
  XCTAssertEqual(try a.store.read("Later.md")["content"] as? String,"sent anyway")
  XCTAssertEqual(try a.store.read("Linked/Inside.md")["content"] as? String,"behind a link on the other device")
  XCTAssertFalse(FileManager.default.fileExists(atPath:a.store.root.appendingPathComponent("Draft.md").path))
  // The next full pass sees the new text and sends it.
  try await pass()
  XCTAssertEqual(try a.store.read("Draft.md")["content"] as? String,"second, longer")
  XCTAssertEqual(try a.peerCursor("B",epoch:b.journalHead().epoch),try b.journalHead().sequence)
 }
 func testOneDocumentThatCannotBeReceivedDoesNotStopTheRestOfThePass()async throws {
  // The paper that will not fit is the first change in the journal, ahead of more than a page of notes.
  try Data(repeating:7,count:2*1024*1024).write(to:a.store.root.appendingPathComponent("Paper.pdf"));try a.scan()
  for i in 0..<150 {try write(a,"Note \(i).md","note \(i)")};try write(a,"Figure.pdf",String(repeating:"f",count:40*1024));a.invalidate();try a.scan()
  try write(b,"From the phone.md","written on this device")
  let secret=Data(repeating:39,count:32),server=PeerTransfer(catalog:a),client=PeerTransfer(catalog:b)
  let(listener,port)=try await listening(secret:secret,server:server);defer{listener.cancel()}
  func pass()async throws {
   let channel=PeerChannel(NWConnection(host:"127.0.0.1",port:port,using:PeerTLS.parameters(secret:secret)));defer{channel.close()}
   try await channel.ready();try await client.synchronize(channel,forceScan:true)
  }
  // Room for everything except the 2 MiB paper: a transfer needs its size plus a 64 MiB reserve.
  b.freeSpace={_ in 65*1024*1024}
  do {try await pass();XCTFail("The document that did not fit must be reported")}catch {XCTAssertTrue(error.localizedDescription.contains("Not enough free space"),error.localizedDescription)}
  XCTAssertFalse(FileManager.default.fileExists(atPath:b.store.root.appendingPathComponent("Paper.pdf").path))
  XCTAssertEqual(try b.manifest(limit:256).filter{!$0.deleted && $0.path.hasPrefix("Note ")}.count,150,"Documents after the failure, on this page and the next, still arrive")
  XCTAssertEqual(try b.store.read("Figure.pdf")["size"] as? Int,40*1024)
  XCTAssertEqual(try a.store.read("From the phone.md")["content"] as? String,"written on this device","This device's own changes are still sent")
  XCTAssertEqual(try b.peerCursor("A",epoch:a.journalHead().epoch),0,"Nothing from the failed document onwards is acknowledged")
  // With room again the next pass is offered the paper once more, and the cursor catches up.
  b.freeSpace={_ in Int64.max};try await pass()
  XCTAssertEqual(try Data(contentsOf:b.store.safeURL("Paper.pdf")).count,2*1024*1024)
  XCTAssertEqual(try b.peerCursor("A",epoch:a.journalHead().epoch),try a.journalHead().sequence)
  // A path this device has to refuse (a folder that is a symbolic link here) is put off the same way.
  try FileManager.default.createSymbolicLink(at:b.store.root.appendingPathComponent("Linked"),withDestinationURL:base)
  try write(a,"Linked/Inside.md","behind a link on the other device");try a.refresh(["Linked/Inside.md"]);try write(a,"Zebra.md","after it");try a.refresh(["Zebra.md"])
  do {try await pass();XCTFail("The refused document must be reported")}catch {XCTAssertTrue(error.localizedDescription.contains("Symbolic links"),error.localizedDescription)}
  XCTAssertEqual(try b.store.read("Zebra.md")["content"] as? String,"after it")
 }
 func testAFailingSearchIndexDoesNotFailASyncedInstall()throws {
  b.store.textLimit=1024
  try write(a,"Export.txt",String(repeating:"too large for the editor ",count:100));try write(a,"Note.md","arrives while the index is unavailable");try a.scan()
  let server=PeerTransfer(catalog:a),client=PeerTransfer(catalog:b)
  func send(_ path:String)throws {
   let offer=try JSONSerialization.jsonObject(with:JSONEncoder().encode(XCTUnwrap(a.entry(path)))) as! [String:Any]
   _ = try client.respond(command:"putSmallBatch",args:server.respond(command:"getSmallBatch",args:["entries":[offer]]))
  }
  // Text over the editor limit installs like any other document.
  try send("Export.txt");XCTAssertEqual(try b.entry("Export.txt"),try a.entry("Export.txt"))
  try b.store.db.execute("CREATE TRIGGER index_unavailable BEFORE INSERT ON docs BEGIN SELECT RAISE(ABORT,'index unavailable'); END")
  try send("Note.md")
  XCTAssertEqual(try String(contentsOf:b.store.safeURL("Note.md"),encoding:.utf8),"arrives while the index is unavailable")
  XCTAssertEqual(try b.entry("Note.md"),try a.entry("Note.md"),"The installed document is recorded")
  XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:b.store.metadata.appendingPathComponent("sync/incoming").path),[],"No staged copy is left behind")
 }
 func testAnUpgradedCatalogKeepsCountingUnderItsDeviceID()throws {
  // A catalog from before replica IDs: its clocks are keyed by the device ID and nothing names a replica.
  let cache=base.appendingPathComponent("legacy-cache"),legacy=try Database(cache.appendingPathComponent("sync.sqlite")),text=Data("written before the upgrade".utf8)
  try legacy.execute("CREATE TABLE entries(path TEXT PRIMARY KEY,hash TEXT,size INTEGER,modified REAL,clock TEXT,deleted INTEGER,seen TEXT)")
  try legacy.execute("INSERT INTO entries VALUES('Note.md',?,?,0,'{\"A\":3}',0,'')",[VaultStore.fingerprint(text),text.count])
  try text.write(to:a.store.root.appendingPathComponent("Note.md"))
  let upgraded=try SyncCatalog(store:VaultStore(root:a.store.root,cache:cache),device:"A")
  XCTAssertEqual(upgraded.replica,"A");try upgraded.scan();XCTAssertEqual(try upgraded.entry("Note.md")?.clock,["A":3])
  try write(upgraded,"Note.md","edited after the upgrade");try upgraded.refresh(["Note.md"])
  XCTAssertEqual(try upgraded.entry("Note.md")?.clock,["A":4])
  XCTAssertEqual(try SyncCatalog(store:upgraded.store,device:"renamed device").replica,"A","The stored replica outlives a change of device ID")
  // A catalog that starts empty is a replica of its own, whatever its device is called, and stays that replica.
  XCTAssertNotEqual(a.replica,"A");XCTAssertNotEqual(a.replica,b.replica);XCTAssertEqual(try SyncCatalog(store:a.store,device:"A").replica,a.replica)
  try a.scan();XCTAssertEqual(try a.entry("Note.md")?.clock,[a.replica:1])
 }
 func testALostCatalogKeepsANewerLocalEditBesideThePeersOlderCopy()throws {
  try write(a,"Note.md","first");try a.scan();try copy(a,b,"Note.md")
  try write(a,"Note.md","second, synced");try a.refresh(["Note.md"]);try copy(a,b,"Note.md")
  // The catalog is lost (the vault folder was renamed, or its cache was cleared); the device ID is unchanged.
  let reopened=try SyncCatalog(store:VaultStore(root:a.store.root,cache:base.appendingPathComponent("ac-lost")),device:"A")
  try write(reopened,"Note.md","third, written after the catalog was lost");try reopened.scan()
  try copy(b,reopened,"Note.md");try copy(reopened,b,"Note.md")
  for e in try b.manifest() where !e.deleted {try copy(b,reopened,e.path)}
  for e in try reopened.manifest() where !e.deleted {try copy(reopened,b,e.path)}
  for c in [reopened,b!] {
   let notes=try c.manifest().filter{!$0.deleted}.map{try String(contentsOf:c.store.safeURL($0.path),encoding:.utf8)}
   XCTAssertEqual(notes.count,2);XCTAssertEqual(Set(notes),Set(["second, synced","third, written after the catalog was lost"]))
  }
  XCTAssertEqual(try reopened.store.read("Note.md")["content"] as? String,try b.store.read("Note.md")["content"] as? String)
 }
 func testALostCatalogWithUnchangedDocumentsMergesWithoutTransferOrConflict()throws {
  try write(a,"Note.md","the same on both sides");try a.scan();try copy(a,b,"Note.md")
  let reopened=try SyncCatalog(store:VaultStore(root:a.store.root,cache:base.appendingPathComponent("ac-lost")),device:"A");try reopened.scan()
  XCTAssertFalse(try b.needs(XCTUnwrap(reopened.entry("Note.md"))));XCTAssertFalse(try reopened.needs(XCTUnwrap(b.entry("Note.md"))))
  XCTAssertEqual(try reopened.entry("Note.md")?.clock,try b.entry("Note.md")?.clock);XCTAssertEqual(try b.entry("Note.md")?.clock.count,2,"The old and the new replica each keep their own counter")
  for c in [reopened,b!] {XCTAssertEqual(try c.manifest().map(\.path),["Note.md"])}
 }
 func testALostCatalogNeitherInventsNorObeysDeletions()throws {
  try write(a,"Removed.md","deleted while the catalog was lost");try write(a,"Restored.md","deleted, synced, then put back");try a.scan();try copy(a,b,"Removed.md");try copy(a,b,"Restored.md")
  try FileManager.default.removeItem(at:a.store.safeURL("Restored.md"));try a.refresh(["Restored.md"]);XCTAssertFalse(try b.needs(XCTUnwrap(a.entry("Restored.md"))))
  // The catalog is lost. One document disappears with nothing to record it; the one the peer saw deleted is put back from a backup.
  try FileManager.default.removeItem(at:a.store.safeURL("Removed.md"));try write(a,"Restored.md","deleted, synced, then put back")
  let reopened=try SyncCatalog(store:VaultStore(root:a.store.root,cache:base.appendingPathComponent("ac-lost")),device:"A");try reopened.scan()
  XCTAssertNil(try reopened.entry("Removed.md"));try copy(b,reopened,"Removed.md")
  XCTAssertEqual(try reopened.store.read("Removed.md")["content"] as? String,"deleted while the catalog was lost")
  // The peer's older tombstone does not delete the restored document; the document goes back to the peer.
  XCTAssertFalse(try reopened.needs(XCTUnwrap(b.entry("Restored.md"))))
  XCTAssertTrue(FileManager.default.fileExists(atPath:try reopened.store.safeURL("Restored.md").path))
  try copy(reopened,b,"Restored.md");XCTAssertEqual(try b.store.read("Restored.md")["content"] as? String,"deleted, synced, then put back")
 }
}
