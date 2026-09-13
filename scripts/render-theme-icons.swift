// The native icon uses the same vector paths as VaultMark.jsx. Deterministic,
// theme-specific artwork can be regenerated without image services or model weights.
import AppKit
let project=URL(fileURLWithPath:CommandLine.arguments[1]),data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])),themes=try JSONSerialization.jsonObject(with:data) as! [[String:Any]],fm=FileManager.default
func color(_ hex:String)->NSColor {let n=UInt32(hex.dropFirst(),radix:16)!;return NSColor(srgbRed:CGFloat((n>>16)&255)/255,green:CGFloat((n>>8)&255)/255,blue:CGFloat(n&255)/255,alpha:1)}
for theme in themes {for mode in ["light","dark"] {
 let id=theme["id"] as! String,name="Vault_"+id.replacingOccurrences(of:"-",with:"_")+"_"+mode,v=theme[mode] as! [String]
 let context=CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:4096,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
 let bounds=NSRect(x:0,y:0,width:1024,height:1024)
 NSGradient(starting:color(v[1]),ending:color(v[2]))!.draw(in:bounds,angle:-60)
 let transform=NSAffineTransform();transform.translateX(by:102,yBy:1024-102);transform.scaleX(by:25.6,yBy:-25.6);transform.concat()
 func path(_ points:Bool)->NSBezierPath {let p=NSBezierPath();if points {p.move(to:NSPoint(x:28,y:3.5));p.curve(to:NSPoint(x:16.8,y:13.2),controlPoint1:NSPoint(x:22.5,y:5.2),controlPoint2:NSPoint(x:18.8,y:8.7));p.line(to:NSPoint(x:16,y:27));p.curve(to:NSPoint(x:28,y:3.5),controlPoint1:NSPoint(x:21.1,y:22.9),controlPoint2:NSPoint(x:25.7,y:14.8))}else{p.move(to:NSPoint(x:4,y:5.5));p.curve(to:NSPoint(x:15.1,y:13.4),controlPoint1:NSPoint(x:9.1,y:6.4),controlPoint2:NSPoint(x:12.2,y:9.4));p.line(to:NSPoint(x:16,y:27));p.curve(to:NSPoint(x:4,y:5.5),controlPoint1:NSPoint(x:11.1,y:24.7),controlPoint2:NSPoint(x:6.4,y:17.4))};p.close();return p}
 NSGraphicsContext.saveGraphicsState();let shadow=NSShadow();shadow.shadowColor=color(v[5]).withAlphaComponent(0.18);shadow.shadowBlurRadius=1.4;shadow.shadowOffset=NSSize(width:0,height:1.5);shadow.set();color(v[9]).withAlphaComponent(0.48).setFill();path(false).fill();color(v[9]).setFill();path(true).fill();NSGraphicsContext.restoreGraphicsState()
 let fold=NSBezierPath();fold.move(to:NSPoint(x:10,y:5.2));fold.line(to:NSPoint(x:16.7,y:10.4));fold.line(to:NSPoint(x:16,y:23.3));fold.line(to:NSPoint(x:14.1,y:12.4));fold.close();color(v[9]).withAlphaComponent(0.23).setFill();fold.fill()
 NSGraphicsContext.restoreGraphicsState()
 let png=NSBitmapImageRep(cgImage:context.makeImage()!).representation(using:.png,properties:[:])!,dir=project.appendingPathComponent("native/Assets.xcassets/"+name+".appiconset")
 try fm.createDirectory(at:dir,withIntermediateDirectories:true);try png.write(to:dir.appendingPathComponent("Icon.png"))
 let contents:[String:Any] = ["images":[["filename":"Icon.png","idiom":"universal","platform":"ios","size":"1024x1024"]],"info":["author":"xcode","version":1]]
 try JSONSerialization.data(withJSONObject:contents,options:.prettyPrinted).write(to:dir.appendingPathComponent("Contents.json"))
 let resources=project.appendingPathComponent("Sources/VaultApp/Resources/icons");try fm.createDirectory(at:resources,withIntermediateDirectories:true);try png.write(to:resources.appendingPathComponent(name+".png"))
}}
