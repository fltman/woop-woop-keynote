import XCTest
import Network
@testable import SlideKit

/// Ansluter till en RIKTIG värd på hemnätet som en scen (som TV:n gör) och rapporterar vad som händer.
/// Körs bara med WOOP_PROBE=<del av namnet>, t.ex. `WOOP_PROBE=Anders swift test --filter Probe`.
@MainActor
final class ProbeTests: XCTestCase {
    func testProbeLiveHost() async throws {
        guard let want = ProcessInfo.processInfo.environment["WOOP_PROBE"] else { throw XCTSkip("WOOP_PROBE ej satt") }
        let browser = HostBrowser()
        browser.start()
        var host: HostBrowser.Host?
        for _ in 0..<100 {
            host = browser.hosts.first { $0.name.contains(want) }
            if host != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        print("PROBE hittade:", browser.hosts.map { "\($0.name) [id \($0.id)]" })
        let h = try XCTUnwrap(host, "ingen värd som heter något med \(want)")
        let s = Session(deck: Deck(title: "probe"), me: Peer(name: "Prob", color: .white, role: .stage),
                        assets: AssetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("probe")))
        s.join(h.endpoint)
        for _ in 0..<80 {
            if s.link != .connecting { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        print("PROBE länk:", s.link, "deck:", s.deck.title, "bilder:", s.deck.slides.count)
        print("PROBE med:", s.peers.map { "\($0.name) (\($0.role.rawValue))" }, "presenterar:", s.present.isPresenting,
              "publikadress:", s.live.audienceURL ?? "ingen")
        XCTAssertEqual(s.link, .connected)
        s.leave()
    }
}
