import XCTest
@testable import VaultCore
final class VaultCoreTests:XCTestCase {
 func testCodeDiscoveryInAnySelectedFolderBeforeIndexing() throws {
  try fixture("Existing folder/baseline.py","print(42)")
  try fixture("Existing folder/Experiment.IPYNB","{\"nbformat\":4,\"cells\":[]}")
  try fixture("Existing folder/Guide.md","[[baseline.py]]")
  XCTAssertEqual(Set(try store.list(parent:"Existing folder").compactMap{$0["path"] as? String}),Set(["Existing folder/baseline.py","Existing folder/Experiment.IPYNB","Existing folder/Guide.md"]))
  XCTAssertEqual(try store.resolve("baseline.py",from:"Existing folder/Guide.md").first?["ext"] as? String,"py")
  XCTAssertEqual(try store.resolve("Experiment.IPYNB",from:"Existing folder/Guide.md").first?["ext"] as? String,"ipynb")
 }
 func testLegacyRulesGainCodeDiscoveryOnceAndPreserveExclusions() throws {
  try fixture(".archii-vault/rules.json","{\"documentExtensions\":[\"md\"],\"excludedDirectories\":[\"private\"],\"excludedPaths\":[\"Research/Skip\"]}")
  try fixture("Research/baseline.py","print(42)")
  try fixture("Research/Experiment.ipynb","{\"cells\":[]}")
  try fixture("Research/Guide.md","[[baseline.py]]")
  try fixture("Research/private/secret.py","hidden")
  try fixture("Research/Skip/secret.ipynb","{}")
  store=try VaultStore(root:root,cache:temp.appendingPathComponent("migrated-cache"))
  XCTAssertEqual(store.rules.excludedDirectories,["private"])
  XCTAssertEqual(store.rules.excludedPaths,["Research/Skip"])
  XCTAssertEqual(Set(try store.list(parent:"Research").compactMap{$0["path"] as? String}),Set(["Research/baseline.py","Research/Experiment.ipynb","Research/Guide.md"]))
  XCTAssertTrue(try store.resolve("private/secret.py",from:"Research/Guide.md").isEmpty)
  XCTAssertEqual(try store.scan()["visited"] as? Int,3)
  XCTAssertEqual(try store.resolve("baseline.py",from:"Research/Guide.md").first?["path"] as? String,"Research/baseline.py")
  let persisted=try JSONDecoder().decode(VaultRules.self,from:Data(contentsOf:root.appendingPathComponent(".archii-vault/rules.json")))
  XCTAssertEqual(persisted.codeDiscoveryVersion,1)
  var custom=persisted;custom.documentExtensions.removeAll{$0=="py"};try store.saveRules(custom)
  store=try VaultStore(root:root,cache:temp.appendingPathComponent("reopened-cache"))
  XCTAssertFalse(store.rules.includes("Research/baseline.py"))
  XCTAssertTrue(store.rules.includes("Research/Experiment.ipynb"))
 }
 func testCodeLinksKeepTheirExtensionAndRelativeFolder() throws {
  var rules=store.rules;rules.documentExtensions=Array(Set(rules.documentExtensions+VaultRules.codeExtensions));try store.saveRules(rules)
  try fixture("Research/Guide.md","[[baseline.py]]\n[Notebook](Starter%20Lab/experiment.ipynb)\n")
  try fixture("Research/Starter Lab/baseline.py","print(42)")
  try fixture("Research/Starter Lab/baseline.md","A note with the same stem")
  try fixture("Research/Starter Lab/experiment.ipynb","{\"nbformat\":4,\"cells\":[]}")
  _ = try store.scan()
  XCTAssertEqual(try store.resolve("baseline.py",from:"Research/Guide.md").first?["path"] as? String,"Research/Starter Lab/baseline.py")
  XCTAssertEqual(try store.resolve("Starter%20Lab/experiment.ipynb",from:"Research/Guide.md").first?["path"] as? String,"Research/Starter Lab/experiment.ipynb")
  XCTAssertEqual(try store.resolve("baseline.md",from:"Research/Guide.md").first?["ext"] as? String,"md")
  XCTAssertTrue(try store.resolve("baseline.swift",from:"Research/Guide.md").isEmpty)
  XCTAssertEqual(try store.backlinks("Research/Starter Lab/baseline.py").count,1)
  XCTAssertEqual(try store.backlinks("Research/Starter Lab/experiment.ipynb").count,1)
  try fixture("Research/Starter Lab/experiment.ipynb","{\"nbformat\":4,\"cells\":[{\"cell_type\":\"markdown\",\"source\":[\"[Guide](../Guide.md)\"]}]}")
  try store.refreshPaths(["Research/Starter Lab/experiment.ipynb"])
  XCTAssertEqual(try store.backlinks("Research/Guide.md").first?["path"] as? String,"Research/Starter Lab/experiment.ipynb")
 }
 func testNewCodeFilesResolveBeforeIndexingWithoutEscapingRules() throws {
  var rules=store.rules;rules.documentExtensions=Array(Set(rules.documentExtensions+VaultRules.codeExtensions));try store.saveRules(rules)
  try fixture("Curriculum/Starter Lab/baseline.py","print(42)")
  try fixture("Curriculum/Notebooks/00 Launch Pad.ipynb","{\"cells\":[]}")
  XCTAssertEqual(try store.resolve("Starter%20Lab/baseline.py",from:"Curriculum/Guide.md").first?["ext"] as? String,"py")
  XCTAssertEqual(try store.resolve("../Notebooks/00%20Launch%20Pad.ipynb",from:"Curriculum/Modules/V02.md").first?["ext"] as? String,"ipynb")
  XCTAssertTrue(try store.resolve("base.py",from:"Curriculum/Guide.md").isEmpty)
  try fixture("node_modules/secret.py","secret")
  XCTAssertTrue(try store.resolve("node_modules/secret.py").isEmpty)
  try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("escape.py"),withDestinationURL:root.appendingPathComponent("Curriculum/Starter Lab/baseline.py"))
  XCTAssertTrue(try store.resolve("escape.py").isEmpty)
 }
 func testBundleAssetsNormalizeTheRootBeforeContainmentCheck() throws {
  let base=URL(fileURLWithPath:"/private/var/containers/Bundle/../Bundle/Application/test/ArchiiVault.app/web")
  let index=try VaultAsset.url(path:"/index.html",root:base)
  XCTAssertEqual(index,base.standardizedFileURL.appendingPathComponent("index.html").standardizedFileURL)
  XCTAssertEqual(try VaultAsset.url(path:"/",root:base),index)
  XCTAssertEqual(try VaultAsset.url(path:"/assets/main.js",root:base).lastPathComponent,"main.js")
  XCTAssertThrowsError(try VaultAsset.url(path:"/../secret",root:base))
  XCTAssertThrowsError(try VaultAsset.url(path:"/%2e%2e/secret",root:base))
  XCTAssertThrowsError(try VaultAsset.url(path:"/x%00.html",root:base))
 }
 func testLocalVaultSurvivesContainerRelocation() throws {
  let old=URL(fileURLWithPath:"/container/old/Documents"),new=URL(fileURLWithPath:"/container/new/Documents")
  let folder=old.appendingPathComponent("Research/My Vault")
  let reference=try XCTUnwrap(LocalVaultReference.relative(folder,documents:old))
  XCTAssertEqual(reference,"Research/My Vault")
  XCTAssertEqual(LocalVaultReference.resolve(reference,documents:new)?.path,"/container/new/Documents/Research/My Vault")
  XCTAssertEqual(LocalVaultReference.relative(try XCTUnwrap(LocalVaultReference.resolve(reference,documents:new)),documents:new),reference)
  XCTAssertNil(LocalVaultReference.relative(URL(fileURLWithPath:"/container/old/Documents-other/vault"),documents:old))
  XCTAssertNil(LocalVaultReference.resolve("../outside",documents:new))
  XCTAssertNil(LocalVaultReference.resolve("/outside",documents:new))
  XCTAssertNil(LocalVaultReference.resolve("folder/../outside",documents:new))
  XCTAssertEqual(LocalVaultReference.resolve(".",documents:new),new)
 }
 var temp:URL!; var root:URL!; var store:VaultStore!
 override func setUpWithError() throws {
  temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);root=temp.appendingPathComponent("vault")
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  store=try VaultStore(root:root,cache:temp.appendingPathComponent("cache"))
 }
 override func tearDownWithError() throws {store=nil;try FileManager.default.removeItem(at:temp)}
 func fixture(_ path:String,_ text:String) throws {let u=root.appendingPathComponent(path);try FileManager.default.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true);try text.write(to:u,atomically:true,encoding:.utf8)}
 func testExclusionsAndIncrementalIndex() throws {
  try fixture("Research/Memory.md","# Memory\nRetrosplenial mechanism [[Other]] #memory")
  try fixture("Other.md","A second document")
  for p in [".git/secret.md","project/node_modules/readme.md",".env","build/private.md"] {try fixture(p,"secret")}
  try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("escape"),withDestinationURL:temp)
  let first=try store.scan();XCTAssertEqual(first["visited"] as? Int,2);XCTAssertEqual(first["updated"] as? Int,2)
  XCTAssertEqual(try store.search("retrosplenial").count,1)
  XCTAssertEqual(try store.search("tag:memory").count,1)
  XCTAssertEqual(try store.backlinks("Other.md").count,1)
  XCTAssertEqual(try store.scan()["updated"] as? Int,0)
  try fixture("Research/Memory.md","A changed hypothesis")
  XCTAssertEqual(try store.scan()["updated"] as? Int,1)
  XCTAssertEqual(try store.search("retrosplenial").count,0)
  try FileManager.default.removeItem(at:root.appendingPathComponent("Other.md"));_ = try store.scan()
  XCTAssertEqual(store.status()["count"] as? Int,1)
 }
 func testPDFRangesPreserveEveryByteAndDetectChanges() throws {
  let data=Data((0..<180000).map{UInt8($0%251)}),url=root.appendingPathComponent("Many pages.pdf")
  try data.write(to:url)
  let first=try store.pdfRange("Many pages.pdf",offset:0,length:65536)
  var reconstructed=Data(base64Encoded:first["data"] as! String)!
  let version=first["version"] as! String
  while reconstructed.count<data.count {let chunk=try store.pdfRange("Many pages.pdf",offset:reconstructed.count,length:65536,version:version);reconstructed.append(Data(base64Encoded:chunk["data"] as! String)!)}
  XCTAssertEqual(reconstructed,data)
  XCTAssertThrowsError(try store.pdfRange("../outside.pdf",offset:0,length:1))
  XCTAssertThrowsError(try store.pdfRange("Many pages.pdf",offset:-1,length:1))
  XCTAssertThrowsError(try store.pdfRange("Many pages.pdf",offset:0,length:2*1024*1024))
  XCTAssertThrowsError(try store.pdfRange("Many pages.pdf",offset:data.count+1,length:1))
  try Data("changed".utf8).write(to:url)
  XCTAssertThrowsError(try store.pdfRange("Many pages.pdf",offset:0,length:1,version:version))
 }
 func testFolderNavigationDoesNotWaitForIndexing() throws {
  try fixture("Research/Experiments/Observation.md","A new note")
  try fixture("Research/Overview.md","A new document")
  try fixture("Research/node_modules/Hidden.md","Excluded")
  try fixture("Research/.hidden.md","Excluded")
  try fixture("Research/source.unknown","Excluded")
  try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("Research/Shortcut.md"),withDestinationURL:root.appendingPathComponent("Research/Overview.md"))
  XCTAssertEqual(try store.list(parent:"Research").compactMap{$0["path"] as? String},["Research/Experiments","Research/Overview.md"])
  XCTAssertEqual(try store.list(parent:"Research/Experiments").first?["title"] as? String,"Observation")
  _ = try store.scan()
  try fixture("Research/Just synced.md","Arrived after the last scan")
  try FileManager.default.removeItem(at:root.appendingPathComponent("Research/Overview.md"))
  XCTAssertEqual(try store.list(parent:"Research").compactMap{$0["path"] as? String},["Research/Experiments","Research/Just synced.md"])
 }
 func testFolderPagesRemainCompleteWhileIndexIsBusy() throws {
  for i in 0..<425 {try fixture(String(format:"Notes/Note %03d.md",i),"A note")}
  try fixture("Notes/Child/Nested.md","Nested")
  let locked=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0),finished=DispatchSemaphore(value:0)
  let index=store.db
  DispatchQueue.global().async {try? index.transaction {locked.signal();release.wait()};finished.signal()}
  locked.wait()
  defer {release.signal();finished.wait()}
  let loaded=expectation(description:"Folder pages load while the index transaction is still open")
  let browser=store!
  DispatchQueue.global().async {
   do {
    let pages=try [0,200,400].map{try browser.list(parent:"Notes",offset:$0)}
    XCTAssertEqual(pages.map{$0.filter{$0["directory"] as? Bool != true}.count},[200,200,25])
    XCTAssertEqual(pages.flatMap{$0}.filter{$0["directory"] as? Bool == true}.count,1)
    XCTAssertEqual(Set(pages.flatMap{$0}.compactMap{$0["path"] as? String}).count,426)
   } catch {XCTFail(error.localizedDescription)}
   loaded.fulfill()
  }
  wait(for:[loaded],timeout:3)
 }
 func testConflictRecoveryAndPortablePaths() throws {
  let doc=try store.save("Research/Note.md",content:"first",revision:nil)
  _ = try store.save("Research/Note.md",content:"second",revision:doc["revision"] as? String)
  XCTAssertThrowsError(try store.save("Research/Note.md",content:"clobber",revision:doc["revision"] as? String))
  XCTAssertEqual(try store.read("Research/Note.md")["content"] as? String,"second")
  let snapshots=try store.recovery("Research/Note.md");XCTAssertEqual(snapshots.count,1)
  XCTAssertEqual(try store.recoveryRead("Research/Note.md",id:snapshots[0]["id"] as! String),"first")
  try store.saveState(["bookmarks":["Research/Note.md"]])
  let copy=temp.appendingPathComponent("drive/another-name");try FileManager.default.createDirectory(at:copy.deletingLastPathComponent(),withIntermediateDirectories:true);try FileManager.default.copyItem(at:root,to:copy)
  let portable=try VaultStore(root:copy,cache:temp.appendingPathComponent("new-cache"));_ = try portable.scan()
  XCTAssertEqual(try portable.state()["bookmarks"] as? [String],["Research/Note.md"])
  XCTAssertEqual(try portable.search("second").count,1)
 }
 func testTraversalAndAmbiguity() throws {
  for p in ["../outside.md",".git/config","x/../../outside.md","node_modules/test.md"] {XCTAssertThrowsError(try store.safeURL(p))}
  try fixture("A/Note.md","one");try fixture("B/Note.md","two");_ = try store.scan()
  XCTAssertEqual(try store.resolve("Note").count,2)
  XCTAssertEqual(try store.resolve("Note",from:"A/Source.md").first?["path"] as? String,"A/Note.md")
 }
 func testGraphPaginationDoesNotTruncateDocumentsOrLinks() throws {
  for i in 0..<420 {try fixture("Notes/Note \(i).md","[[Note \((i+1)%420)]]")}
  _ = try store.scan()
  for kind in ["nodes","links"] {
   var cursor=0,more=true,ids=Set<Int>()
   while more {let page=try store.graphPage(kind:kind,after:cursor,limit:37),rows=page["items"] as! [[String:Any]];for row in rows{XCTAssertTrue(ids.insert(row["id"] as! Int).inserted)};cursor=page["cursor"] as! Int;more=page["more"] as! Bool}
   XCTAssertEqual(ids.count,420)
  }
 }
 func testMovePreservesLinksAndRejectsCollision() throws {
  try fixture("Old/Subject.md","# Subject\nSee [[Neighbor]].")
  try fixture("Old/Neighbor.md","Nearby")
  try fixture("Index.md","[[Old/Subject#Heading|Alias]] and [source](Old/Subject.md#Heading)")
  _ = try store.scan()
  let original=try store.read("Old/Subject.md")
  _ = try store.move("Old/Subject.md",to:"New/Renamed.md",revision:original["revision"] as! String)
  let index=try store.read("Index.md")["content"] as! String
  XCTAssertTrue(index.contains("[[New/Renamed#Heading|Alias]]"));XCTAssertTrue(index.contains("(New/Renamed.md#Heading)"))
  XCTAssertTrue((try store.read("New/Renamed.md")["content"] as! String).contains("[[Old/Neighbor]]"))
  XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("Old/Subject.md").path))
  let renamed=try store.read("New/Renamed.md")
  XCTAssertThrowsError(try store.move("New/Renamed.md",to:"Index.md",revision:renamed["revision"] as! String))
 }

}
