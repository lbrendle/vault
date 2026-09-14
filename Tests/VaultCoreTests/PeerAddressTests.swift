import XCTest
@testable import VaultCore

final class PeerAddressTests:XCTestCase {
    func testLANAndTailscaleRoutes()throws {
        for host in ["192.168.1.20","10.0.1.2","172.16.0.1","100.64.0.1","100.127.255.254","mac.tail123.ts.net","macbook.local"] {
            let route=try PeerAddress(host+":50000");XCTAssertEqual(route.host,host);XCTAssertEqual(route.port,50000)
        }
    }
    func testInvalidAndPublicRoutesAreRejected() {
        for value in ["100.63.1.1:80","100.128.0.1:80","8.8.8.8:80","192.168.1.999:80","192.168.1.2:0","10.0.0.1:65536","https://mac.ts.net:443","mac.tail.ts.net.evil.com:80","-bad.tail.ts.net:80","mac..ts.net:80","010.0.0.1:80","localhost:80","mac.local:80/path"] {XCTAssertThrowsError(try PeerAddress(value),value)}
    }
}
