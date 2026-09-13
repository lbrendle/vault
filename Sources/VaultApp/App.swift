import SwiftUI
import WebKit
import VaultCore
#if os(macOS)
import AppKit
#endif

@main struct VaultApp:App {
 #if os(macOS)
 @NSApplicationDelegateAdaptor(VaultApplicationDelegate.self) private var appDelegate
 #endif
 var body:some Scene {
  WindowGroup {
       #if os(macOS)
       VaultWebView().frame(minWidth:820,minHeight:560).ignoresSafeArea(.container,edges:.top)
       #else
       VaultWebView().ignoresSafeArea(.all)
       #endif
   }
   .defaultSize(width:1380,height:900)
   #if os(macOS)
   .windowStyle(.hiddenTitleBar)
   #endif
 }
}
#if os(macOS)
final class VaultApplicationDelegate:NSObject,NSApplicationDelegate {
 func applicationWillFinishLaunching(_ notification:Notification) {
  guard let id=Bundle.main.bundleIdentifier else{return}
  if let existing=NSRunningApplication.runningApplications(withBundleIdentifier:id).first(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}) {
   existing.activate(options:[.activateAllWindows]);NSApplication.shared.terminate(nil)
  }
 }
}
struct VaultWebView:NSViewRepresentable {
 func makeCoordinator()->Bridge {
  let bridge=Bridge(webRoot:Bundle.main.resourceURL!.appendingPathComponent("web"))
  let args=CommandLine.arguments
  let override=args.firstIndex(of:"--vault").flatMap{$0+1<args.count ? args[$0+1]:nil}
  if let path=override ?? UserDefaults.standard.string(forKey:"vaultPath") {bridge.initialRoot=URL(fileURLWithPath:path)}
  return bridge
 }
 func makeNSView(context:Context)->NSView {
  let config=WKWebViewConfiguration();config.setURLSchemeHandler(context.coordinator,forURLScheme:"vault")
  config.websiteDataStore = .nonPersistent()
  config.userContentController.addScriptMessageHandler(context.coordinator,contentWorld:.page,name:"vault")
  config.userContentController.addUserScript(WKUserScript(source:"window.addEventListener('error',e=>window.webkit.messageHandlers.vault.postMessage({method:'logError',args:{message:e.message}}));",injectionTime:.atDocumentStart,forMainFrameOnly:true))
  let web=WKWebView(frame:.zero,configuration:config);web.setValue(true,forKey:"drawsBackground");web.navigationDelegate=context.coordinator;web.uiDelegate=context.coordinator;context.coordinator.web=web
  let container=NSView(frame:.zero)
  web.autoresizingMask=[.width,.height]
  container.addSubview(web)
  DispatchQueue.main.async{web.window?.titlebarAppearsTransparent=true;web.window?.isOpaque=true}
  web.load(URLRequest(url:URL(string:"vault://app/index.html")!));return container
 }
 func updateNSView(_ view:NSView,context:Context){}
}
#else
/// UIKit owns keyboard avoidance. The web page fills this view's available area
/// and never subtracts visualViewport height a second time.
final class KeyboardWorkspace:UIView {
 let web:WKWebView
 private var lastKeyboardOpen:Bool?
 private var fullBottom:NSLayoutConstraint!
 private var keyboardBottom:NSLayoutConstraint!
 init(web:WKWebView) {
  self.web=web;super.init(frame:.zero)
  web.translatesAutoresizingMaskIntoConstraints=false;addSubview(web)
  keyboardLayoutGuide.followsUndockedKeyboard=false
  keyboardLayoutGuide.usesBottomSafeArea=false
  fullBottom=web.bottomAnchor.constraint(equalTo:bottomAnchor)
  keyboardBottom=web.bottomAnchor.constraint(equalTo:keyboardLayoutGuide.topAnchor)
  NSLayoutConstraint.activate([
   web.topAnchor.constraint(equalTo:topAnchor),web.leadingAnchor.constraint(equalTo:leadingAnchor),
   web.trailingAnchor.constraint(equalTo:trailingAnchor),fullBottom
  ])
 }
 required init?(coder:NSCoder){fatalError("init(coder:) is unavailable")}
 override func layoutSubviews() {
  super.layoutSubviews()
  let height=keyboardLayoutGuide.layoutFrame.height
  let open=height>150 // Floating hardware-keyboard controls are not a docked keyboard.
  if open != lastKeyboardOpen {lastKeyboardOpen=open;fullBottom.isActive = !open;keyboardBottom.isActive=open;setNeedsLayout();web.evaluateJavaScript("document.documentElement.dataset.keyboard='\(open ? "open":"closed")'") {_,_ in}}
 }
}
struct VaultWebView:UIViewRepresentable {
 func makeCoordinator()->Bridge {
  let bridge=Bridge(webRoot:Bundle.main.resourceURL!.appendingPathComponent("web"))
  let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
  if let relative=UserDefaults.standard.string(forKey:"localVaultRelativePath") {bridge.initialRoot=LocalVaultReference.resolve(relative,documents:documents)}
  if bridge.initialRoot==nil,let data=UserDefaults.standard.data(forKey:"vaultBookmark") {
   var stale=false
   if let url=try? URL(resolvingBookmarkData:data,options:[],relativeTo:nil,bookmarkDataIsStale:&stale) { _ = url.startAccessingSecurityScopedResource();bridge.scopedURL=url;bridge.initialRoot=url }
  }
  if bridge.initialRoot==nil,let path=UserDefaults.standard.string(forKey:"vaultPath"),path.hasPrefix(FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].path+"/"){bridge.initialRoot=URL(fileURLWithPath:path)}
  if let index=CommandLine.arguments.firstIndex(of:"--vault"),index+1<CommandLine.arguments.count {bridge.initialRoot=URL(fileURLWithPath:CommandLine.arguments[index+1])}
  return bridge
 }
 func makeUIView(context:Context)->KeyboardWorkspace {
  let config=WKWebViewConfiguration();config.setURLSchemeHandler(context.coordinator,forURLScheme:"vault");config.userContentController.addScriptMessageHandler(context.coordinator,contentWorld:.page,name:"vault");config.websiteDataStore = .nonPersistent()
  config.userContentController.addUserScript(WKUserScript(source:"window.addEventListener('error',e=>window.webkit.messageHandlers.vault.postMessage({method:'logError',args:{message:e.message}}));",injectionTime:.atDocumentStart,forMainFrameOnly:true))
  config.userContentController.addUserScript(WKUserScript(source:"window.__nativeKeyboardLayout=true;",injectionTime:.atDocumentStart,forMainFrameOnly:true))
  let web=WKWebView(frame:.zero,configuration:config)
  // Keep WebKit pan recognition enabled for nested overflow panes. The fixed
  // CSS shell owns root overflow and UIKit owns keyboard avoidance.
  web.scrollView.isScrollEnabled=true;web.scrollView.bounces=false
  web.scrollView.alwaysBounceVertical=false;web.scrollView.alwaysBounceHorizontal=false
  web.scrollView.contentInsetAdjustmentBehavior = .never
  web.scrollView.automaticallyAdjustsScrollIndicatorInsets=false
  web.isOpaque=false;web.backgroundColor = .clear;web.scrollView.backgroundColor = .clear
  context.coordinator.web=web;web.navigationDelegate=context.coordinator;web.uiDelegate=context.coordinator;web.load(URLRequest(url:URL(string:"vault://app/index.html")!));return KeyboardWorkspace(web:web)
 }
 func updateUIView(_ view:KeyboardWorkspace,context:Context){}
}
#endif
