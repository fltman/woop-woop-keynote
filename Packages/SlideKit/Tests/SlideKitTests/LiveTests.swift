import XCTest
import Network
import AVFoundation
@testable import SlideKit

@MainActor
final class LiveTests: XCTestCase {
    func store() -> AssetStore {
        AssetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID())"))
    }
    func waitUntil(_ what: String, _ cond: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<250 { if cond() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail("väntade förgäves på: \(what)")
    }

    func testJinglesAreValidWav() {
        for j in Jingle.allCases {
            let s = j.samples()
            XCTAssertGreaterThan(s.count, 5000, j.rawValue)
            XCTAssertLessThanOrEqual(s.map { abs($0) }.max() ?? 0, 1.0, j.rawValue)
            XCTAssertGreaterThan(s.map { abs($0) }.max() ?? 0, 0.3, "\(j.rawValue) är nästan tyst")
            let w = j.wav()
            XCTAssertEqual(String(data: w.prefix(4), encoding: .ascii), "RIFF")
            XCTAssertEqual(w.count, 44 + s.count * 2)
            // Den inspelade effekten följer med och går att spela.
            XCTAssertNotEqual(j.data(), w, "\(j.rawValue).mp3 saknas i paketet")
            XCTAssertGreaterThan((try? AVAudioPlayer(data: j.data()))?.duration ?? 0, 0.4, j.rawValue)
        }
    }

    func testVanishToggleAndHidden() {
        var slide = Slide()
        let a = Element(frame: Frame(x: 0, y: 0, w: 10, h: 10), content: .shape(ShapeBox(kind: .star, fill: .black)), reveal: .spin)
        let b = Element(frame: Frame(x: 0, y: 0, w: 10, h: 10), content: .shape(ShapeBox(kind: .star, fill: .black)), vanish: true)
        slide.elements = [a, b]
        var s = PresentState(isPresenting: true)
        XCTAssertEqual(s.hidden(on: slide), [a.id])
        s = s.togglingGone(b.id)
        XCTAssertEqual(s.hidden(on: slide), [a.id, b.id])
        s = s.togglingGone(b.id)
        XCTAssertEqual(s.hidden(on: slide), [a.id])
    }

    /// Reaktioner, streck och röster når alla; publikens webbsida röstar över HTTP.
    func testLiveEventsAndVotingOverNetwork() async throws {
        var deck = Deck.new(title: "Quiz")
        let poll = Element(frame: Frame(x: 100, y: 100, w: 1600, h: 800),
                           content: .poll(PollBox(question: "Störst?", options: ["Etna", "Vesuvius", "Hekla"], correct: 0,
                                                  accent: .black, textColor: .white)))
        deck.slides[0].elements.append(poll)
        let host = Session(deck: deck, me: Peer(name: "Ida", color: Peer.palette[0]), assets: store())
        host.requireApproval = false
        try host.startHosting(advertise: false)
        try await waitUntil("lyssnar") { host.hostPort != nil && host.live.audienceURL != nil }
        let port = NWEndpoint.Port(rawValue: host.hostPort!)!
        let tv = Session(deck: .new(title: "t"), me: Peer(name: "TV", color: Peer.palette[2], role: .stage), assets: store())
        let kid = Session(deck: .new(title: "k"), me: Peer(name: "Leo", color: Peer.palette[1]), assets: store())
        tv.join(.hostPort(host: "127.0.0.1", port: port)); kid.join(.hostPort(host: "127.0.0.1", port: port))
        try await waitUntil("inne") { tv.link == .connected && kid.link == .connected }
        try await waitUntil("tv fick adressen") { tv.live.audienceURL == host.live.audienceURL }

        kid.send(.reaction(1))
        host.send(.stroke(InkStroke(points: [Spot(x: 1, y: 2)], color: .black)))
        host.send(.jingle(.tada, nonce: UUID()))
        try await waitUntil("reaktion, streck och ljud på tv") {
            tv.live.reactions.count == 1 && tv.live.ink.count == 1 && tv.live.jingle == .tada && host.live.reactions.count == 1
        }
        kid.send(.votes(poll: poll.id, counts: [99, 0, 0]))   // bara värden får räkna röster
        XCTAssertNil(kid.live.votes[poll.id])

        // Ingen fråga förrän någon presenterar bilden.
        XCTAssertNil(host.currentPoll)
        host.setPresent(PresentState(isPresenting: true, slideIndex: 0))
        XCTAssertEqual(host.currentPoll?.id, poll.id)
        host.castVote(poll: poll.id, option: 1, voter: "a")
        host.castVote(poll: poll.id, option: 1, voter: "b")
        host.castVote(poll: poll.id, option: 0, voter: "a")   // byter sig
        host.castVote(poll: poll.id, option: 7, voter: "c")   // finns inte
        try await waitUntil("ställningen på tv") { tv.live.votes[poll.id] == [1, 1, 0] }

        // Över HTTP, som publikens mobiler gör.
        let base = URL(string: host.live.audienceURL!.replacingOccurrences(of: #"//[^:]+:"#, with: "//127.0.0.1:", options: .regularExpression))!
        let (page, _) = try await URLSession.shared.data(from: base)
        XCTAssertTrue(String(decoding: page, as: UTF8.self).contains("Woop Woop"))
        let (voted, _) = try await URLSession.shared.data(from: URL(string: "/vote?poll=\(poll.id)&option=2&voter=web1", relativeTo: base)!)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: voted) as? [String: Any])
        let p = try XCTUnwrap(json["poll"] as? [String: Any])
        XCTAssertEqual(p["mine"] as? Int, 2)
        XCTAssertNil(p["correct"], "rätt svar får inte läcka innan det visas")
        try await waitUntil("webbrösten räknad") { tv.live.votes[poll.id] == [1, 1, 1] }
        _ = try await URLSession.shared.data(from: URL(string: "/react?e=2", relativeTo: base)!)
        try await waitUntil("webbreaktion") { tv.live.reactions.count == 2 }

        host.send(.answer(poll: poll.id, shown: true))
        host.castVote(poll: poll.id, option: 0, voter: "sen")
        try await waitUntil("svaret visas") { tv.live.answers.contains(poll.id) }
        XCTAssertEqual(host.live.votes[poll.id], [1, 1, 1], "inga röster efter att svaret visats")

        host.send(.pointer(Spot(x: 5, y: 5)))
        host.send(.stroke(InkStroke(points: [Spot(x: 1, y: 2)], color: .black)))
        host.remote(.stop)   // bildbyte eller slut rensar streck och pekare
        XCTAssertTrue(host.live.ink.isEmpty); XCTAssertNil(host.live.pointer)
        host.stopHosting()
    }
}
