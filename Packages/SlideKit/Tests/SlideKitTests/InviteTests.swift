import XCTest
import Network
@testable import SlideKit

@MainActor
final class InviteTests: XCTestCase {
    func testPhoneInvitesTVWithItsSharedName() async throws {
        let beacon = TVBeacon(name: "Testrum")
        var got: String?
        beacon.onInvite = { got = $0 }
        beacon.start()
        for _ in 0..<100 where beacon.port == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let port = try XCTUnwrap(beacon.port)

        let s = Session(deck: .new(title: "Vulkaner"), me: Peer(name: "Ida", color: Peer.palette[0]),
                        assets: AssetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("inv-\(UUID())")))
        XCTAssertEqual(s.role, .solo)
        s.invite(tv: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!))
        XCTAssertEqual(s.role, .host, "att välja en TV betyder att man delar")
        for _ in 0..<100 where got == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(got, s.shareKey, "TV:n får presentationens fasta id, inte namnet")
        s.stopHosting(); beacon.stop()
    }
}
