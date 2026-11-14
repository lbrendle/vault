import XCTest
import CoreGraphics
#if os(macOS)
@testable import Vault
#else
@testable import ArchiiVault
#endif

/// Geometry only: no hinge is needed. The sizes are the points an iPhone Duo's
/// inner display reports upright (669 x 951) and turned (951 x 669).
final class FoldReportTests:XCTestCase {
 let upright=CGRect(x:0,y:0,width:669,height:951),turned=CGRect(x:0,y:0,width:951,height:669)
 func testFlatDisplayHasNoFold() {
  XCTAssertNil(FoldReport.describe(divisions:[],in:upright))
  XCTAssertNil(FoldReport.describe(divisions:[CGRect(x:334.5,y:0,width:0,height:951)],in:upright))
  XCTAssertNil(FoldReport.describe(divisions:[.null],in:upright))
 }
 func testUprightBendSplitsLeftAndRight() {
  XCTAssertEqual(FoldReport.describe(divisions:[CGRect(x:322,y:0,width:25,height:951)],in:upright),FoldReport(axis:.vertical,start:322,size:25))
 }
 func testTurnedBendSplitsTopAndBottom() {
  XCTAssertEqual(FoldReport.describe(divisions:[CGRect(x:0,y:322,width:951,height:25)],in:turned),FoldReport(axis:.horizontal,start:322,size:25))
 }
 func testBendIsMeasuredFromTheViewOrigin() {
  let inset=CGRect(x:40,y:10,width:600,height:900)
  XCTAssertEqual(FoldReport.describe(divisions:[CGRect(x:322,y:0,width:25,height:951)],in:inset),FoldReport(axis:.vertical,start:282,size:25))
 }
 func testRegionsThatDoNotSplitTheViewAreIgnored() {
  // A strip along an edge, a region outside the view, and one covering all of it leave nothing to arrange around.
  XCTAssertNil(FoldReport.describe(divisions:[CGRect(x:0,y:0,width:25,height:951)],in:upright))
  XCTAssertNil(FoldReport.describe(divisions:[CGRect(x:700,y:0,width:25,height:951)],in:upright))
  XCTAssertNil(FoldReport.describe(divisions:[upright],in:upright))
  XCTAssertNil(FoldReport.describe(divisions:[CGRect(x:300,y:400,width:60,height:60)],in:upright))
 }
 func testFirstUsableDivisionWins() {
  let report=FoldReport.describe(divisions:[CGRect(x:0,y:0,width:25,height:951),CGRect(x:322,y:0,width:25,height:951)],in:upright)
  XCTAssertEqual(report?.axis,.vertical);XCTAssertEqual(report?.start,322)
 }
 func testPayloadMatchesTheWebContract() {
  let payload=FoldReport(axis:.horizontal,start:322,size:25).payload
  XCTAssertEqual(payload["axis"] as? String,"horizontal")
  XCTAssertEqual(payload["start"] as? Double,322)
  XCTAssertEqual(payload["size"] as? Double,25)
  XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
 }
}
