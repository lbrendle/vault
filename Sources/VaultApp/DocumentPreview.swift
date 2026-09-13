import Foundation
#if os(macOS)
import AppKit
import PDFKit
import Quartz
final class DocumentPreview:NSObject,QLPreviewPanelDataSource {
 private var item:URL?,windows=[NSWindow]()
 func open(_ url:URL){
  if url.pathExtension.lowercased()=="pdf" {
   let view=PDFView();view.autoScales=true;view.displayMode = .singlePageContinuous;view.document=PDFDocument(url:url)
   let thumbnails=PDFThumbnailView();thumbnails.pdfView=view;thumbnails.thumbnailSize=NSSize(width:90,height:120)
   let split=NSSplitView();split.isVertical=true;split.dividerStyle = .thin;split.addArrangedSubview(thumbnails);split.addArrangedSubview(view)
   let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:800),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.title=url.lastPathComponent;window.contentView=split;window.isReleasedWhenClosed=false;window.center();window.makeKeyAndOrderFront(nil);split.setPosition(140,ofDividerAt:0);windows.removeAll{!$0.isVisible};windows.append(window)
  }else{item=url;if let panel=QLPreviewPanel.shared(){panel.dataSource=self;panel.reloadData();panel.makeKeyAndOrderFront(nil)}}
 }
 func numberOfPreviewItems(in panel:QLPreviewPanel!)->Int{item==nil ? 0:1}
 func previewPanel(_ panel:QLPreviewPanel!,previewItemAt index:Int)->(any QLPreviewItem)!{item as NSURL?}
}
#else
import UIKit
import QuickLook
final class DocumentPreview:NSObject,QLPreviewControllerDataSource {
 private var item:URL?
 func open(_ url:URL){
  item=url;let preview=QLPreviewController();preview.dataSource=self;preview.modalPresentationStyle = .fullScreen
  let scene=UIApplication.shared.connectedScenes.first as? UIWindowScene;var presenter=scene?.windows.first(where:{$0.isKeyWindow})?.rootViewController
  while let next=presenter?.presentedViewController{presenter=next};presenter?.present(preview,animated:true)
 }
 func numberOfPreviewItems(in controller:QLPreviewController)->Int{item==nil ? 0:1}
 func previewController(_ controller:QLPreviewController,previewItemAt index:Int)->any QLPreviewItem{item! as NSURL}
}
#endif
