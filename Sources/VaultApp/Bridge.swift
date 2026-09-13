import Foundation
import WebKit
import VaultCore
#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

final class Bridge:NSObject,WKScriptMessageHandlerWithReply,WKURLSchemeHandler,WKNavigationDelegate,WKUIDelegate {
    weak var web:WKWebView?
    private var pageReady=false
    private var iconUpdate:DispatchWorkItem?
    private var changedFiles=Set<String>()
    private var fileEventTimer:DispatchWorkItem?
    var store:VaultStore?
    var initialRoot:URL?
    var sync:DeviceSync?
    let preview=DocumentPreview()
    let io=DispatchQueue(label:"vault.documents",qos:.userInitiated)
    let indexQueue=DispatchQueue(label:"vault.index",qos:.utility)
    let readQueue=DispatchQueue(label:"vault.reader",qos:.userInitiated,attributes:.concurrent)
    #if os(macOS)
    var watcher:VaultWatcher?
    #endif
    var localModel:LocalModel?
    #if os(iOS)
    var importingModel=false
    var pickerReply:((Any?,String?)->Void)?
    var scopedURL:URL?
    #endif
    var webRoot:URL
    init(webRoot:URL) {self.webRoot=webRoot;super.init()}
    static func vaultIdentity(_ root:URL)->String {
        #if os(iOS)
        let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        if let relative=LocalVaultReference.relative(root,documents:documents){return "local-vault:"+relative}
        #endif
        return root.path
    }
    func connect(_ root:URL) throws {
        let hash=VaultStore.fingerprint(Data(Self.vaultIdentity(root).utf8))
        let cache=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Archii Vault/Cache/"+hash)
        sync?.stop()
        store=try VaultStore(root:root,cache:cache)
        UserDefaults.standard.set(root.path,forKey:"vaultPath")
        #if os(iOS)
        let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        if let relative=LocalVaultReference.relative(root,documents:documents) {
            UserDefaults.standard.set(relative,forKey:"localVaultRelativePath")
            UserDefaults.standard.removeObject(forKey:"vaultBookmark")
        }else{UserDefaults.standard.removeObject(forKey:"localVaultRelativePath")}
        #endif
        if let store {
            sync=DeviceSync(store:store,emit:{[weak self] data in self?.event("sync",data)},changed:{[weak self] paths in self?.event("files",["paths":paths]);if paths.isEmpty{self?.event("sharedState",[:])}});sync?.start()
            indexQueue.async { _ = try? store.scan() }
            #if os(macOS)
            let vaultSync=sync
            DispatchQueue.global(qos:.utility).async { [weak self] in
            let watcher=VaultWatcher(path:store.root.path){[weak self] paths,rescan in
                let relative=paths.filter{$0.hasPrefix(store.root.path+"/")}.map{String($0.dropFirst(store.root.path.count+1))}.filter{store.rules.includes($0)}
                if relative.isEmpty && !rescan{return}
                // File propagation must not wait behind full-text parsing of
                // other large documents. Keep this bound to the watched vault.
                vaultSync?.documentsChanged(relative)
                self?.indexQueue.async {
                    if rescan {_ = try? store.scan()}else{try? store.refreshPaths(relative)}
                    if self?.store === store {self?.event("files",["paths":relative])}
                }
            }
            DispatchQueue.main.async {if self?.store === store {self?.watcher=watcher}}
            }
            #endif
        }
    }
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage,replyHandler:@escaping (Any?,String?)->Void) {
        guard message.frameInfo.isMainFrame, let request=message.body as? [String:Any], let method=request["method"] as? String else {replyHandler(nil,"Invalid request");return}
        let args=request["args"] as? [String:Any] ?? [:]
        if method=="initialize" {
            let root=initialRoot;initialRoot=nil
            io.async {do {if let root{try self.connect(root)};let result=self.store?.status() ?? ["connected":false];DispatchQueue.main.async{replyHandler(result,nil)}}catch{DispatchQueue.main.async{replyHandler(nil,error.localizedDescription)}}};return
        }
        if method=="logError" {NSLog("Vault interface error: %@",args["message"] as? String ?? "Unknown");replyHandler(true,nil);return}
        if method=="platform" {
            #if os(macOS)
            replyHandler(["name":"mac"],nil)
            #else
            replyHandler(["name":"ios"],nil)
            #endif
            return
        }
        if method=="appearance" {
            #if os(macOS)
            NSApp.appearance=NSAppearance(named:(args["mode"] as? String)=="light" ? .aqua:.darkAqua)
            if let hex=args["background"] as? String,hex.count==7,hex.first=="#",let rgb=UInt32(hex.dropFirst(),radix:16) {
                let color=NSColor(srgbRed:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:1)
                web?.underPageBackgroundColor=color;web?.window?.backgroundColor=color
                web?.needsDisplay=true
            }
            #else
            let style:UIUserInterfaceStyle=(args["mode"] as? String)=="light" ? .light:.dark
            let hex=(args["background"] as? String ?? (style == .light ? "#ffffff":"#212121")).replacingOccurrences(of:"#",with:"")
            if hex.count==6,let rgb=UInt32(hex,radix:16) {
                let color=UIColor(red:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:1)
                web?.backgroundColor=color;web?.scrollView.backgroundColor=color;web?.superview?.backgroundColor=color;web?.window?.backgroundColor=color
            }
            web?.overrideUserInterfaceStyle=style;web?.window?.overrideUserInterfaceStyle=style
            web?.window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
            #endif
            let theme=(args["theme"] as? String ?? "graphite").replacingOccurrences(of:"-",with:"_"),mode=(args["mode"] as? String)=="dark" ? "dark":"light",match=args["matchIcon"] as? Bool ?? true
            let iconName="Vault_"+theme+"_"+mode
            iconUpdate?.cancel()
            let work=DispatchWorkItem{[weak self] in
                #if os(macOS)
                if match,let root=self?.webRoot.deletingLastPathComponent(),let image=NSImage(contentsOf:root.appendingPathComponent("icons/"+iconName+".png")) {
                    let rounded=NSImage(size:NSSize(width:1024,height:1024));rounded.lockFocus();NSBezierPath(roundedRect:NSRect(x:56,y:56,width:912,height:912),xRadius:205,yRadius:205).addClip();image.draw(in:NSRect(x:56,y:56,width:912,height:912));rounded.unlockFocus();NSApp.applicationIconImage=rounded
                }else{NSApp.applicationIconImage=nil}
                #else
                let app=UIApplication.shared,desired=match ? iconName:nil
                let icons=Bundle.main.object(forInfoDictionaryKey:"CFBundleIcons") as? [String:Any],alternates=icons?["CFBundleAlternateIcons"] as? [String:Any]
                if app.applicationState == .active,app.supportsAlternateIcons,app.alternateIconName != desired,(!match || alternates?[iconName] != nil) {app.setAlternateIconName(desired){error in if let error {NSLog("Vault icon: %@",error.localizedDescription)}}}
                #endif
            };iconUpdate=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.6,execute:work)
            replyHandler(true,nil);return
        }
        if ["starterModels","downloadStarterModel","pauseStarterDownload"].contains(method) {
            Task { @MainActor in
                let downloads=StarterDownloads.shared
                downloads.onChange={ [weak self] state in self?.event("modelDownload",state) }
                do {
                    if method=="downloadStarterModel" {try downloads.start(args["id"] as? String ?? "")}
                    if method=="pauseStarterDownload" {downloads.pause()}
                    replyHandler(try downloads.catalog(),nil)
                }catch{replyHandler(nil,error.localizedDescription)}
            }
            return
        }
        if method=="selectModel" {UserDefaults.standard.set(args["id"] as? String,forKey:"selectedModel");replyHandler(true,nil);return}
        if method=="models" {
            io.async{var result=ModelLibrary.catalog()
                let defaults=UserDefaults.standard
                let previous=defaults.string(forKey:"selectedModel") ?? ""
                let installed=result["models"] as? [[String:Any]] ?? []
                if !installed.contains(where:{$0["id"] as? String==previous}),!previous.hasPrefix("remote/") {
                    let preferred=installed.first(where:{$0["recommended"] as? Bool==true}) ?? installed.first
                    defaults.set(preferred?["id"] as? String ?? "",forKey:"selectedModel")
                }
                result["selected"]=defaults.string(forKey:"selectedModel") ?? ""
                #if os(iOS)
                result["remoteOption"]=true
                #endif
                DispatchQueue.main.async{replyHandler(result,nil)}
            };return
        }
        if method=="modelFolder" {
            try? FileManager.default.createDirectory(at:ModelLibrary.root,withIntermediateDirectories:true)
            #if os(macOS)
            NSWorkspace.shared.open(ModelLibrary.root)
            #else
            if let url=URL(string:"shareddocuments://"+ModelLibrary.root.path.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!) {UIApplication.shared.open(url)}
            #endif
            replyHandler(true,nil);return
        }
        if method=="importModel" {
            #if os(macOS)
            let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.allowsMultipleSelection=false;panel.message="Choose a model folder containing config.json, tokenizer files, and .safetensors weights."
            if panel.runModal() == .OK,let url=panel.url {io.async{do{_ = try ModelLibrary.importFolder(url);let value=ModelLibrary.catalog();DispatchQueue.main.async{replyHandler(value,nil)}}catch{DispatchQueue.main.async{replyHandler(nil,error.localizedDescription)}}}}else{replyHandler(nil,"Cancelled")}
            #else
            importingModel=true;pickerReply=replyHandler
            let picker=UIDocumentPickerViewController(forOpeningContentTypes:[.folder],asCopy:false);picker.delegate=self
            web?.window?.rootViewController?.present(picker,animated:true)
            #endif
            return
        }
        if method=="copy" {
            #if os(macOS)
            NSPasteboard.general.clearContents();NSPasteboard.general.setString(args["text"] as? String ?? "",forType:.string)
            #else
            UIPasteboard.general.string=args["text"] as? String ?? ""
            #endif
            replyHandler(true,nil);return
        }
        if method=="createLocalVault" {
            io.async{do {let root=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("My Vault");try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try self.connect(root);let status=self.store?.status();DispatchQueue.main.async{replyHandler(status,nil)}}catch{DispatchQueue.main.async{replyHandler(nil,error.localizedDescription)}}};return
        }
        if method=="chooseVault" {
            #if os(macOS)
            let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.allowsMultipleSelection=false;panel.message="Open a local document vault. No files will be uploaded."
            if panel.runModal() == .OK,let url=panel.url {io.async{do {try self.connect(url);let status=self.store?.status();DispatchQueue.main.async{replyHandler(status,nil)}}catch{DispatchQueue.main.async{replyHandler(nil,error.localizedDescription)}}}}else{replyHandler(nil,"Cancelled")}
            #else
            pickerReply=replyHandler
            let picker=UIDocumentPickerViewController(forOpeningContentTypes:[.folder],asCopy:false);picker.delegate=self;picker.allowsMultipleSelection=false
            let scene=UIApplication.shared.connectedScenes.first as? UIWindowScene
            var presenter=scene?.windows.first(where:{$0.isKeyWindow})?.rootViewController
            while let next=presenter?.presentedViewController {presenter=next}
            presenter?.present(picker,animated:true)
            #endif
            return
        }
        if method=="openExternal" {
            guard let s=args["url"] as? String,let url=URL(string:s),["https","http","mailto"].contains(url.scheme?.lowercased() ?? "") else {replyHandler(nil,"Unsupported external link");return}
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
            replyHandler(true,nil);return
        }
        if method=="reveal" || method=="openNative" {
            do {
                let url=try storeRequired().safeURL(args["path"] as? String ?? "")
                #if os(macOS)
                if method=="reveal" {NSWorkspace.shared.activateFileViewerSelecting([url])}else{preview.open(url)}
                #else
                preview.open(url)
                #endif
                replyHandler(true,nil)
            }catch{replyHandler(nil,error.localizedDescription)};return
        }
        if method=="print" {
            #if os(macOS)
            if let web {web.printOperation(with:NSPrintInfo.shared).run()}
            #endif
            replyHandler(true,nil);return
        }
        if method=="modelStatus" || method=="modelChat" || method=="modelStop" {
            if method=="modelStop" {localModel?.stop();sync?.model(method,args:args,event:{_ in},reply:{_,_ in});replyHandler(true,nil);return}
            #if os(iOS)
            if method=="modelStatus" || (args["model_id"] as? String).map({$0=="paired-mac" || $0.hasPrefix("remote/")})==true {
                if let sync {sync.model(method,args:args,event:{[weak self] e in self?.event("model",e)},reply:replyHandler)}else{replyHandler(nil,"Open a vault and pair it with your Mac in Settings → Device sync.")}
                return
            }
            #else
            if method=="modelStatus" {replyHandler(ModelLibrary.catalog(),nil);return}
            #endif
            if localModel==nil{localModel=LocalModel(emit:{[weak self] e in self?.event("model",e)})}
            localModel?.call(args,reply:replyHandler)
            return
        }
        if method=="pdfResource" {
            let folders=["cMapUrl":"cmaps","standardFontDataUrl":"standard_fonts","wasmUrl":"wasm"]
            guard let folder=folders[args["kind"] as? String ?? ""],let name=args["filename"] as? String,!name.isEmpty,name==URL(fileURLWithPath:name).lastPathComponent else{replyHandler(nil,"Invalid PDF resource");return}
            readQueue.async {do {let url=try VaultAsset.url(path:"/pdf/\(folder)/\(name)",root:self.webRoot),data=try Data(contentsOf:url);DispatchQueue.main.async{replyHandler(data.base64EncodedString(),nil)}}catch{DispatchQueue.main.async{replyHandler(nil,error.localizedDescription)}}};return
        }
        guard let selected=store else {if method=="status" {replyHandler(["connected":false],nil)}else{replyHandler(nil,"Open a vault first")};return}
        if method.hasPrefix("sync") {sync?.call(method,args:args,reply:replyHandler);return}
        // Reading bytes must not queue behind search, graph or metadata work.
        if method=="read" {readQueue.async {do {let result=try selected.read(args["path"] as? String ?? "");DispatchQueue.main.async{replyHandler(result,nil)}}catch{DispatchQueue.main.async{replyHandler(nil,error.localizedDescription)}}};return}
        if method=="pdfRange" {readQueue.async {do {let result=try selected.pdfRange(args["path"] as? String ?? "",offset:args["offset"] as? Int ?? 0,length:args["length"] as? Int ?? 65536,version:args["version"] as? String);DispatchQueue.main.async{replyHandler(result,nil)}}catch{DispatchQueue.main.async{replyHandler(nil,error.localizedDescription)}}};return}
        if method=="scan" {indexQueue.async {do {let result=try selected.scan();DispatchQueue.main.async{replyHandler(result,nil)}}catch{DispatchQueue.main.async{replyHandler(nil,error.localizedDescription)}}};return}
        io.async {
            do {
                let result:Any
                let path=args["path"] as? String ?? ""
                switch method {
                case "status":result=selected.status()
                case "list":result=try selected.list(parent:path,offset:args["offset"] as? Int ?? 0)
                case "search":result=try selected.search(args["query"] as? String ?? "",offset:args["offset"] as? Int ?? 0)
                case "retrieve":let terms=(args["terms"] as? [String] ?? []).prefix(6).filter{!$0.isEmpty}.map{"\""+$0.replacingOccurrences(of:"\"",with:"\"\"")+"\""};result=terms.isEmpty ? []:try selected.db.execute("SELECT d.path,d.title,snippet(search,2,'','',' … ',80) AS snippet FROM search JOIN docs d ON d.id=search.rowid WHERE search MATCH ? ORDER BY bm25(search) LIMIT 5",[terms.joined(separator:" OR ")])
                case "save":result=try selected.save(path,content:args["content"] as? String ?? "",revision:args["revision"] as? String)
                case "move":result=try selected.move(path,to:args["destination"] as? String ?? "",revision:args["revision"] as? String ?? "")
                case "folder":try selected.folder(path);result=true
                case "trash":try selected.trash(path,revision:args["revision"] as? String);result=true
                case "resolve":result=try selected.resolve(args["target"] as? String ?? "",from:path)
                case "backlinks":result=try selected.backlinks(path)
                case "outgoing":result=try selected.db.execute("SELECT target FROM links WHERE source=? LIMIT 300",[path])
                case "graphPage":result=try selected.graphPage(kind:args["kind"] as? String ?? "nodes",after:args["after"] as? Int ?? 0)
                case "tags":result=try selected.db.execute("SELECT tag,count(*) AS count FROM tags GROUP BY tag ORDER BY count DESC LIMIT 400")
                case "state":result=try selected.state()
                case "saveState":try selected.saveState(args);result=true
                case "recovery":result=try selected.recovery(path)
                case "recoveryRead":result=try selected.recoveryRead(path,id:args["id"] as? String ?? "")
                case "rules":result=try JSONSerialization.jsonObject(with:JSONEncoder().encode(selected.rules))
                case "saveRules":let value=try JSONDecoder().decode(VaultRules.self,from:JSONSerialization.data(withJSONObject:args));try selected.saveRules(value);result=true
                case "baseRows":let folder=args["folder"] as? String ?? "";result=try selected.db.execute("SELECT path,title,ext,size,modified,frontmatter FROM docs WHERE parent=? AND ext='md' ORDER BY title COLLATE NOCASE LIMIT 1000",[folder])
                default:throw VaultError.message("Unknown action: "+method)
                }
                if ["save","trash","move"].contains(method){self.sync?.documentsChanged([path,args["destination"] as? String ?? ""].filter{!$0.isEmpty})}
                DispatchQueue.main.async{replyHandler(result,nil)}
            }catch {DispatchQueue.main.async{replyHandler(nil,error.localizedDescription)}}
        }
    }
    #if os(macOS)
    func webView(_ webView:WKWebView,runJavaScriptAlertPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping()->Void) {
        let alert=NSAlert();alert.messageText=message;alert.addButton(withTitle:"OK");alert.runModal();completionHandler()
    }
    func webView(_ webView:WKWebView,runJavaScriptConfirmPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping(Bool)->Void) {
        let alert=NSAlert();alert.messageText=message;alert.addButton(withTitle:"Continue");alert.addButton(withTitle:"Cancel");completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
    func webView(_ webView:WKWebView,runJavaScriptTextInputPanelWithPrompt prompt:String,defaultText:String?,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping(String?)->Void) {
        let alert=NSAlert();alert.messageText=prompt;let field=NSTextField(frame:NSRect(x:0,y:0,width:420,height:26));field.stringValue=defaultText ?? "";alert.accessoryView=field;alert.addButton(withTitle:"Save");alert.addButton(withTitle:"Cancel");alert.window.initialFirstResponder=field;completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue:nil)
    }
    #else
    private func present(_ alert:UIAlertController) {
        let scene=UIApplication.shared.connectedScenes.first as? UIWindowScene
        var presenter=scene?.windows.first(where:{$0.isKeyWindow})?.rootViewController
        while let next=presenter?.presentedViewController {presenter=next}
        presenter?.present(alert,animated:true)
    }
    func webView(_ webView:WKWebView,runJavaScriptAlertPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping()->Void) {
        let a=UIAlertController(title:message,message:nil,preferredStyle:.alert);a.addAction(UIAlertAction(title:"OK",style:.default){_ in completionHandler()});present(a)
    }
    func webView(_ webView:WKWebView,runJavaScriptConfirmPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping(Bool)->Void) {
        let a=UIAlertController(title:message,message:nil,preferredStyle:.alert);a.addAction(UIAlertAction(title:"Continue",style:.default){_ in completionHandler(true)});a.addAction(UIAlertAction(title:"Cancel",style:.cancel){_ in completionHandler(false)});present(a)
    }
    func webView(_ webView:WKWebView,runJavaScriptTextInputPanelWithPrompt prompt:String,defaultText:String?,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping(String?)->Void) {
        let a=UIAlertController(title:prompt,message:nil,preferredStyle:.alert);a.addTextField{$0.text=defaultText};a.addAction(UIAlertAction(title:"Save",style:.default){_ in completionHandler(a.textFields?.first?.text)});a.addAction(UIAlertAction(title:"Cancel",style:.cancel){_ in completionHandler(nil)});present(a)
    }
    #endif
    func storeRequired() throws -> VaultStore {guard let store else{throw VaultError.message("Open a vault first")};return store}
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {pageReady=true}
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView){pageReady=false;webView.reload()}
    func event(_ name:String,_ data:[String:Any]) {
        if name=="files" {
            DispatchQueue.main.async{[weak self] in guard let self else{return};self.changedFiles.formUnion(data["paths"] as? [String] ?? []);guard self.fileEventTimer==nil else{return};let timer=DispatchWorkItem{[weak self] in guard let self else{return};let paths=Array(self.changedFiles);self.changedFiles=[];self.fileEventTimer=nil;self.sendEvent("files",["paths":paths])};self.fileEventTimer=timer;DispatchQueue.main.asyncAfter(deadline:.now()+0.3,execute:timer)};return
        }
        sendEvent(name,data)
    }
    private func sendEvent(_ name:String,_ data:[String:Any]) {
        DispatchQueue.main.async { [weak self] in
            guard self?.pageReady==true,let encoded=try? JSONSerialization.data(withJSONObject:["name":name,"data":data]),let text=String(data:encoded,encoding:.utf8) else{return}
            self?.web?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('vault-event',{detail:\(text)}))",completionHandler:nil)
        }
    }
    func webView(_ webView:WKWebView,start urlSchemeTask:WKURLSchemeTask) {
        guard let url=urlSchemeTask.request.url else{return}
        do {
            let target:URL
            if url.host=="app" {
                target=try VaultAsset.url(path:url.path,root:webRoot)
            } else if url.host=="document" {target=try storeRequired().safeURL(String(url.path.dropFirst()))}
            else {throw VaultError.message("Invalid local URL")}
            let size=(try target.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
            guard size<80*1024*1024 else{throw VaultError.message("Open this large attachment with its native viewer")}
            let types=["html":"text/html","js":"application/javascript","css":"text/css","svg":"image/svg+xml","png":"image/png","jpg":"image/jpeg","jpeg":"image/jpeg","webp":"image/webp","gif":"image/gif","woff2":"font/woff2","woff":"font/woff","ttf":"font/ttf","pdf":"application/pdf","wasm":"application/wasm","mp3":"audio/mpeg","m4a":"audio/mp4","mp4":"video/mp4"]
            let data=try Data(contentsOf:target,options:.mappedIfSafe)
            urlSchemeTask.didReceive(URLResponse(url:url,mimeType:types[target.pathExtension] ?? "application/octet-stream",expectedContentLength:data.count,textEncodingName:nil));urlSchemeTask.didReceive(data);urlSchemeTask.didFinish()
        }catch{NSLog("Vault asset: %@",error.localizedDescription);urlSchemeTask.didFailWithError(error)}
    }
    func webView(_ webView:WKWebView,stop urlSchemeTask:WKURLSchemeTask) {}
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping (WKNavigationActionPolicy)->Void) {
        if navigationAction.request.url?.scheme=="vault" || navigationAction.request.url?.absoluteString=="about:blank" {decisionHandler(.allow)}else{decisionHandler(.cancel)}
    }
}

#if os(iOS)
extension Bridge:UIDocumentPickerDelegate {
    func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
        guard let url=urls.first else{pickerReply?(nil,"No folder selected");return}
        if importingModel {
            importingModel=false;let reply=pickerReply;pickerReply=nil
            let access=url.startAccessingSecurityScopedResource()
            io.async{defer{if access{url.stopAccessingSecurityScopedResource()}};do{_ = try ModelLibrary.importFolder(url);let value=ModelLibrary.catalog();DispatchQueue.main.async{reply?(value,nil)}}catch{DispatchQueue.main.async{reply?(nil,error.localizedDescription)}}};return
        }
        scopedURL?.stopAccessingSecurityScopedResource();_ = url.startAccessingSecurityScopedResource();scopedURL=url
        let reply=pickerReply;pickerReply=nil
        io.async {do {let bookmark=try url.bookmarkData(options:[],includingResourceValuesForKeys:nil,relativeTo:nil);UserDefaults.standard.set(bookmark,forKey:"vaultBookmark");try self.connect(url);let status=self.store?.status();DispatchQueue.main.async{reply?(status,nil)}}catch{DispatchQueue.main.async{reply?(nil,error.localizedDescription)}}}
    }
    func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController){pickerReply?(nil,"Cancelled");pickerReply=nil;importingModel=false}
}
#endif
