import XCTest
import VaultCore
#if os(iOS)
@testable import ArchiiVault

final class LabDeviceTests:XCTestCase {
    var root:URL!
    override func setUpWithError() throws {
        root=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("Lab Verification "+UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    }
    func call(_ method:String,_ args:[String:Any]=[:])async throws->[String:Any] {
        try await withCheckedThrowingContinuation { continuation in
            LabRuntime.shared.call(method,args:args,root:root){value,error in
                if let error{continuation.resume(throwing:NSError(domain:"LabTests",code:1,userInfo:[NSLocalizedDescriptionKey:error]))}
                else if let value=value as? [String:Any]{continuation.resume(returning:value)}
                else{continuation.resume(throwing:NSError(domain:"LabTests",code:2))}
            }
        }
    }
    func run(_ code:String,mode:String="cell",timeout:Int=120)async throws->[String:Any]{
        let result=try await call("labRun",["project":"First experiment","code":code,"path":"device-verification.py","mode":mode,"timeout":timeout])
        let data=try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
        XCTAssertEqual(result["status"] as? String,"ok",String(decoding:data.prefix(12000),as:UTF8.self))
        return result
    }
    func testNativePythonScienceAndGPU()async throws {
        let catalog=try await call("labProjects")
        XCTAssertEqual(catalog["local"] as? Bool,true)
        _ = try await run("import sys, platform, numpy, pandas, matplotlib, sympy, networkx, sqlite3, pytest, dulwich\nprint(sys.version)\nprint(platform.machine())\nprint({m.__name__:getattr(m,'__version__','bundled') for m in [numpy,pandas,matplotlib,sympy,networkx]})")
        // Force Python networking to fail. All following cells must use bundled files and local compute.
        _ = try await run("import socket\n_original_socket = socket.socket\nclass NoNetwork(socket.socket):\n    def connect(self, *args, **kwargs):\n        raise RuntimeError('Network disabled during local verification')\nsocket.socket = NoNetwork")
        var evidence=[[String:Any]]()
        for filename in ["01 First experiment.ipynb","02 Train on the GPU.ipynb","03 Mathematics.ipynb","04 Write a Metal kernel.ipynb"] {
            let file=try await call("labRead",["project":"First experiment","path":filename])
            var document=try JSONSerialization.jsonObject(with:Data((file["content"] as! String).utf8)) as! [String:Any]
            var executed=[[String:Any]]()
            var count=0
            for var cell in document["cells"] as! [[String:Any]] {
                guard cell["cell_type"] as? String=="code" else{executed.append(cell);continue}
                let code=(cell["source"] as! [String]).joined()
                let result=try await run(code)
                count += 1;cell["outputs"]=result["outputs"];cell["execution_count"]=count;executed.append(cell)
                evidence.append(["notebook":filename,"id":result["id"]!,"status":result["status"]!,"seconds":result["seconds"]!])
            }
            document["cells"]=executed
            let savedText=String(decoding:try JSONSerialization.data(withJSONObject:document,options:[.prettyPrinted,.withoutEscapingSlashes]),as:UTF8.self)
            _ = try await call("labSave",["project":"First experiment","path":filename,"content":savedText,"revision":file["revision"]!])
            let reopened=try await call("labRead",["project":"First experiment","path":filename])
            XCTAssertEqual(reopened["content"] as? String,savedText)
        }
        _ = try await run("assert __import__('locale').getpreferredencoding(False).lower().replace('-','') == 'utf8'\nfrom pathlib import Path\nPath('unicode.txt').write_text('Café · Δυναμική 🧠')\nassert Path('unicode.txt').read_text() == 'Café · Δυναμική 🧠'")
        _ = try await run("from vaultlab import metal as mx\nloss, gradient = mx.value_and_grad(lambda p: (p[0]*p[0]).sum())([numpy.array([1.,2.])])\nassert loss == 5.0\nnumpy.testing.assert_allclose(gradient[0], [2.,4.])")
        _ = try await run("python baseline.py --self-check",mode:"console")
        _ = try await run("python baseline.py --out runs/baseline-01 --seed 7 --events 800",mode:"console")
        _ = try await run("pytest -q",mode:"console")
        _ = try await run("git init",mode:"console")
        _ = try await run("git add .",mode:"console")
        _ = try await run("git commit -m 'Verified local experiment'",mode:"console")
        _ = try await run("git status",mode:"console")
        _ = try await run("git log",mode:"console")
        _ = try await run("socket.socket = _original_socket")
        let record:[String:Any]=["root":root.path,"tests":evidence,"pythonNetworkingDisabled":true,"date":ISO8601DateFormatter().string(from:Date())]
        let data=try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:root.appendingPathComponent("verification.json"))
        let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");attachment.name="Local iPad lab verification";attachment.lifetime = .keepAlways;add(attachment)
    }
    func testNotebookUsesInstalledLocalModel()async throws {
        _ = try await call("labProjects")
        _ = try await run("from vaultlab import models\ninstalled = models.list()\nprint('Installed local models:', len(installed))")
        guard !(ModelLibrary.catalog()["models"] as? [[String:Any]] ?? []).isEmpty else{throw XCTSkip("Install a Vault model to exercise native notebook generation.")}
        _ = try await run("reply = models.chat([{'role':'user','content':'Say hello in one short sentence.'}], max_tokens=64, temperature=0.0, timeout=120)\nassert reply['local'] and reply['offline']\nassert reply['text'].strip()\nprint(reply)",timeout:150)
        _ = try await run("from vaultlab import metal\nassert metal.info()['local']\nprint('GPU is available after model unload')")
    }
    func testPairedMacOverLAN()async throws {
        guard let pairingCode=ProcessInfo.processInfo.environment["VAULT_LAB_QA_CODE"] else{throw XCTSkip("Run alongside the isolated Mac LAN fixture")}
        _ = try await call("labProjects")
        let store=try VaultStore(root:root,cache:root.appendingPathComponent(".cache"))
        let peer=DeviceSync(store:store,emit:{_ in},changed:{_ in});defer{peer.stop()}
        let _:Any=try await withCheckedThrowingContinuation{c in peer.call("syncJoin",args:["code":pairingCode]){v,e in if let e{c.resume(throwing:VaultError.message(e))}else{c.resume(returning:v ?? [:])}}}
        func remote(_ method:String,_ args:[String:Any]=[:])async throws->[String:Any]{try await withCheckedThrowingContinuation{c in var forwarded=args;forwarded["address"]=ProcessInfo.processInfo.environment["VAULT_LAB_QA_ADDRESS"] ?? "";peer.lab(method,args:forwarded){v,e in if let e{c.resume(throwing:VaultError.message(e))}else{c.resume(returning:v as? [String:Any] ?? [:])}}}}
        var available=false
        for _ in 0..<30 {
            if let status=try? await remote("labRemoteStatus"),status["enabled"] as? Bool==true{available=true;break}
            try await Task.sleep(nanoseconds:2_000_000_000)
        }
        XCTAssertTrue(available,"No paired lab host was discovered")
        guard available else{return}
        let manifest=try await call("labManifest",["project":"First experiment"])
        let code="import numpy as np\nimport scipy, sklearn, subprocess, sys, platform\nfrom scipy import signal\nnp.testing.assert_allclose(signal.savgol_filter(np.arange(9.),5,2),np.arange(9.),atol=1e-12)\nassert subprocess.check_output([sys.executable,'-c','print(42)'],text=True).strip()=='42'\nprint('Paired Mac: SciPy, scikit-learn and an actual subprocess verified')\nprint(platform.platform())"
        let result=try await remote("labRemoteRun",["job":UUID().uuidString,"project":"First experiment","path":"lan-fixture.py","code":code,"manifest":manifest["files"]!])
        XCTAssertEqual(result["status"] as? String,"ok",String(describing:result["outputs"]))
        XCTAssertEqual(result["execution"] as? String,"paired-mac")
        let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
        let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");attachment.name="Paired Mac LAN result";attachment.lifetime = .keepAlways;add(attachment)
    }
    func testExistingVaultCodeRunsAndSavesInPlace()async throws {
        let folder=root.appendingPathComponent("Curriculum/Starter Lab")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let script=folder.appendingPathComponent("baseline.py")
        try "answer = 6 * 7\nprint(answer)\n".write(to:script,atomically:true,encoding:.utf8)
        try "{\"nbformat\":4,\"cells\":[]}".write(to:folder.appendingPathComponent("Experiment.ipynb"),atomically:true,encoding:.utf8)
        let metadata=root.appendingPathComponent(".archii-vault")
        try FileManager.default.createDirectory(at:metadata,withIntermediateDirectories:true)
        try "{\"documentExtensions\":[\"md\"],\"excludedDirectories\":[\"private\"],\"excludedPaths\":[]}".write(to:metadata.appendingPathComponent("rules.json"),atomically:true,encoding:.utf8)
        let store=try VaultStore(root:root,cache:root.appendingPathComponent(".cache"))
        XCTAssertEqual(Set(try store.list(parent:"Curriculum/Starter Lab").compactMap{$0["ext"] as? String}),Set(["py","ipynb"]))
        XCTAssertEqual(try store.resolve("baseline.py",from:"Curriculum/Starter Lab/Guide.md").first?["ext"] as? String,"py")
        XCTAssertEqual(try store.resolve("Experiment.ipynb",from:"Curriculum/Starter Lab/Guide.md").first?["ext"] as? String,"ipynb")
        let project="@/Curriculum/Starter Lab"
        let file=try await call("labRead",["project":project,"path":"baseline.py"])
        let result=try await call("labRun",["project":project,"path":"baseline.py","code":file["content"]!])
        XCTAssertEqual(result["status"] as? String,"ok")
        let edited="answer = 43\nprint(answer)\n"
        _ = try await call("labSave",["project":project,"path":"baseline.py","content":edited,"revision":file["revision"]!])
        XCTAssertEqual(try String(contentsOf:script,encoding:.utf8),edited)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("Labs/Starter Lab/baseline.py").path))
        do{_ = try await call("labRead",["project":"@/../outside","path":"private.py"]);XCTFail("Escaped the vault") }catch{}
    }
    func testInstallPurePythonPackage()async throws {
        _ = try await call("labProjects")
        _ = try await run("%pip install more-itertools==10.5.0 ipython",timeout:300)
        _ = try await run("from more_itertools import chunked\nassert list(chunked(range(5), 2)) == [[0,1],[2,3],[4]]\nprint('Installed and imported a pure Python package on iPad')")
        _ = try await run("import IPython\nfrom IPython.display import HTML\nassert IPython.version_info >= (9, 0)\nassert HTML('<b>Vault</b>').data == '<b>Vault</b>'\nprint('IPython installed and imported on this device')")
        _ = try await run("!pip install ipython\nimport IPython\nprint(IPython.__version__)")
    }
    func testFilesSessionsAndInvalidInputs()async throws {
        _ = try await call("labProjects")
        let first=try await call("labSave",["project":"First experiment","path":"nested/check.py","content":"answer = 6 * 7\n"])
        _ = try await run("python nested/check.py",mode:"console")
        _ = try await run("assert answer == 42\nprint(answer)")
        do{_ = try await call("labSave",["project":"First experiment","path":"nested/check.py","content":"lost update","revision":"wrong"]);XCTFail("Stale write was accepted")}catch{}
        _ = try await call("labSave",["project":"First experiment","path":"nested/check.py","content":"answer = 43\n","revision":first["revision"]!])
        do{_ = try await call("labRead",["project":"First experiment","path":"../../outside"]);XCTFail("Traversal was accepted")}catch{}
        let error=try await call("labRun",["project":"First experiment","code":"raise ValueError('expected failure')","path":"bad.py"])
        XCTAssertEqual(error["status"] as? String,"error")
        let timeout=try await call("labRun",["project":"First experiment","code":"while True: pass","timeout":1])
        XCTAssertEqual(timeout["status"] as? String,"interrupted")
        _ = try await run("print('The session is usable after interruption')")
    }
}

#endif
