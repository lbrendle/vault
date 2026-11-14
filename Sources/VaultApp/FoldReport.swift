import CoreGraphics

/// Where a partly closed folding display bends across the app's window.
///
/// The window is flat, and there is no report, on every device without a hinge
/// and on a folding iPhone that is fully open or showing its outer display.
/// The web interface reads the report through `fold.js`.
struct FoldReport:Equatable {
 enum Axis:String {
  /// The bend runs top to bottom: two pages side by side.
  case vertical
  /// The bend runs side to side: a top half above a bottom half.
  case horizontal
 }
 let axis:Axis
 /// Distance from the window's left edge (vertical) or top edge (horizontal) to the bend.
 let start:CGFloat
 /// Thickness of the strip that controls should stay out of.
 let size:CGFloat
 var payload:[String:Any] {["axis":axis.rawValue,"start":Double(start),"size":Double(size)]}

 /// Picks the division that splits `bounds` into two usable parts.
 /// `divisions` are the active division regions UIKit reports for a view, in
 /// that view's coordinate space; a flat display reports none or an empty one.
 static func describe(divisions:[CGRect],in bounds:CGRect)->FoldReport? {
  for division in divisions {
   let strip=division.intersection(bounds)
   guard !strip.isNull,strip.width>0,strip.height>0 else{continue}
   let spansHeight=strip.height>=bounds.height*0.9,spansWidth=strip.width>=bounds.width*0.9
   if spansHeight,!spansWidth,strip.minX>bounds.minX,strip.maxX<bounds.maxX {return FoldReport(axis:.vertical,start:strip.minX-bounds.minX,size:strip.width)}
   if spansWidth,!spansHeight,strip.minY>bounds.minY,strip.maxY<bounds.maxY {return FoldReport(axis:.horizontal,start:strip.minY-bounds.minY,size:strip.height)}
  }
  return nil
 }
}
