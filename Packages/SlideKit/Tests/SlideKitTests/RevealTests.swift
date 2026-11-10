import XCTest
import Network
@testable import SlideKit

@MainActor
final class RevealTests: XCTestCase {
    func deck() -> (Deck, a: UUID, b: UUID) {
        var d = Deck.new(title: "R")
        let a = Element(frame: Frame(x: 0, y: 0, w: 10, h: 10), content: .shape(ShapeBox(kind: .star, fill: .black)), reveal: .pop)
        let plain = Element(frame: Frame(x: 0, y: 0, w: 10, h: 10), content: .shape(ShapeBox(kind: .heart, fill: .black)))
        let b = Element(frame: Frame(x: 0, y: 0, w: 10, h: 10), content: .text(TextBox(text: "x")), reveal: .flyUp, sound: "abc.m4a")
        d.slides[0].elements += [a, plain, b]
        d.slides.append(Slide())
        return (d, a.id, b.id)
    }

    func testNextRevealsInOrderThenAdvances() {
        let (d, a, b) = deck()
        var s = PresentState(isPresenting: true)
        s = s.next(in: d); XCTAssertEqual(s.revealed, [a]); XCTAssertNil(s.sound)
        s = s.next(in: d); XCTAssertEqual(s.revealed, [a, b]); XCTAssertEqual(s.sound?.asset, "abc.m4a")
        let cue = s.sound
        s = s.next(in: d); XCTAssertEqual(s.slideIndex, 1); XCTAssertEqual(s.revealed, [])
        // Bakåt: färdigbyggd.
        s = s.previous(in: d); XCTAssertEqual(s.slideIndex, 0); XCTAssertEqual(Set(s.revealed), [a, b])
        // Tryck på ett synligt element med ljud spelar det igen (ny nonce).
        let again = s.playing(b, in: d).sound
        XCTAssertEqual(again?.asset, "abc.m4a"); XCTAssertNotEqual(again?.nonce, cue?.nonce)
        // Sista bilden: nästa gör ingenting.
        let last = PresentState(isPresenting: true, slideIndex: 1)
        XCTAssertEqual(last.next(in: d), last)
    }

    func testTVRemoteRevealsOverNetwork() async throws {
        let (d, a, b) = deck()
        func store() -> AssetStore { AssetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("rv-\(UUID())")) }
        let host = Session(deck: d, me: Peer(name: "Ida", color: Peer.palette[0]), assets: store())
        try host.startHosting(advertise: false)
        while host.hostPort == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let tv = Session(deck: .new(), me: Peer(name: "TV", color: .white, role: .stage), assets: store())
        tv.join(.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: host.hostPort!)!))
        while tv.link != .connected { try await Task.sleep(nanoseconds: 20_000_000) }
        tv.remote(.start); tv.remote(.next); tv.remote(.next)
        for _ in 0..<100 where tv.present.revealed.count < 2 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(tv.present.revealed, [a, b])
        XCTAssertEqual(tv.present.sound?.element, b, "TV:n får ljudsignalen och kan spela den")
        host.stopHosting()
    }
}
