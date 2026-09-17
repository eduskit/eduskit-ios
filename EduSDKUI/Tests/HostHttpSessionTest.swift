import XCTest
@testable import EduSDK

final class HostHttpSessionTest: XCTestCase {
    func testLocalDevHostAcceptsEduskitSuffix() {
        XCTAssertTrue(HostHttpSession.isLocalDevHost("sdk.eduskit.com"))
        XCTAssertTrue(HostHttpSession.isLocalDevHost("sdk.draw.eduskit.com"))
        XCTAssertTrue(HostHttpSession.isLocalDevHost("API.IM.EDUSKIT.COM"))
        XCTAssertTrue(HostHttpSession.isLocalDevHost("eduskit.com"))
    }

    func testLocalDevHostRejectsUnrelatedHosts() {
        XCTAssertFalse(HostHttpSession.isLocalDevHost("example.com"))
        XCTAssertFalse(HostHttpSession.isLocalDevHost("eduskit.com.evil"))
        XCTAssertFalse(HostHttpSession.isLocalDevHost(""))
    }

    func testPrintableAsciiKeepsMkcertIssuer() {
        var raw = Data([0x30, 0x00, 0x06])
        raw.append(contentsOf: Array("mkcert bleem@192.168.1.182".utf8))
        raw.append(0x00)
        XCTAssertTrue(HostHttpSession.issuerContainsMkcert(HostHttpSession.printableAscii(from: raw)))
    }

    func testMkcertIssuerMarker() {
        XCTAssertTrue(HostHttpSession.issuerContainsMkcert("mkcert bleem@192.168.1.182"))
        XCTAssertTrue(HostHttpSession.issuerContainsMkcert("CN=MKCERT local"))
        XCTAssertFalse(HostHttpSession.issuerContainsMkcert("Let's Encrypt"))
        XCTAssertFalse(HostHttpSession.issuerContainsMkcert(""))
    }

    func testLocalDevFallbackRequiresHostAndIssuer() {
        XCTAssertTrue(
            HostHttpSession.allowsLocalDevFallback(
                host: "sdk.eduskit.com",
                issuerText: "mkcert bleem@192.168.1.182"
            )
        )
        XCTAssertFalse(
            HostHttpSession.allowsLocalDevFallback(
                host: "sdk.eduskit.com",
                issuerText: "Let's Encrypt"
            )
        )
        XCTAssertFalse(
            HostHttpSession.allowsLocalDevFallback(
                host: "evil.example",
                issuerText: "mkcert bleem@192.168.1.182"
            )
        )
    }
}
