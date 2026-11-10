import XCTest
import Network
@testable import SlideKit

@MainActor
final class SyncTests: XCTestCase {
    func tmpStore() -> AssetStore {
        AssetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("ww-\(UUID().uuidString)"))
    }

    func waitUntil(_ what: String, timeout: Double = 5, _ cond: @escaping @MainActor () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !cond() {
            if Date() > end { XCTFail("tidsgräns: \(what)"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func text(_ t: String, x: Double = 100) -> Element {
        Element(frame: Frame(x: x, y: 100, w: 400, h: 100), content: .text(TextBox(text: t)))
    }

    func testOpsUndoRedo() {
        var d = Deck.new(title: "T")
        let s = d.slides[0].id
        let e = text("hej")
        let ops: [Op] = [
            .upsertElement(slide: s, e, at: nil),
            .insertSlide(Slide(), at: 1),
            .moveElement(slide: s, element: e.id, to: 0),
            .setTitle("Ny"),
        ]
        var history: [Deck] = [d]
        var inverses: [Op] = []
        for op in ops {
            inverses.append(d.inverse(of: op)!)
            XCTAssertTrue(d.apply(op))
            history.append(d)
        }
        for (inv, expected) in zip(inverses.reversed(), history.dropLast().reversed()) {
            d.apply(inv)
            XCTAssertEqual(d.slides, expected.slides)
            XCTAssertEqual(d.title, expected.title)
        }
        // Idempotens: samma bild två gånger blir inte två bilder.
        let sl = Slide()
        d.apply(.insertSlide(sl, at: 0))
        XCTAssertFalse(d.apply(.insertSlide(sl, at: 0)))
    }

    func testActivityFeed() {
        let me = Peer(name: "Ida", color: Peer.palette[0])
        let s = Session(deck: .new(title: "T"), me: me, assets: tmpStore())
        let slide = s.deck.slides[0].id
        var e = text("V")
        s.perform(.upsertElement(slide: slide, e, at: nil))
        for t in ["Vu", "Vul", "Vulkaner är heta"] {
            if case .text(var tb) = e.content { tb.text = t; e.content = .text(tb) }
            s.perform(.upsertElement(slide: slide, e, at: nil))
        }
        // Skrivandet blir EN rad som visar texten så långt den kommit.
        XCTAssertEqual(s.activity.map(\.text), ["Ida lade till en text på bild 1", "Ida skriver: »Vulkaner är heta«"])
        XCTAssertNotNil(s.recentEdits[e.id])
        // Anteckningar är privata: inget i flödet.
        let sl = s.deck.slides[0]
        s.perform(.setSlideProps(slide, background: sl.background, notes: "hemligt", transition: sl.transition))
        XCTAssertFalse(s.activity.contains { $0.text.contains("hemligt") || $0.text.contains("anteckning") })
        XCTAssertEqual(s.activity.count, 2)
        // Kameran följer: ny bild → fokus dit, bildbyte → fokus dit.
        let ny = Slide()
        s.perform(.insertSlide(ny, at: 1))
        XCTAssertEqual(s.focusSlide, ny.id)
        s.setPresence(slide: slide)
        XCTAssertEqual(s.focusSlide, slide)
        XCTAssertEqual(s.activity.last?.text, "Ida lade till bild 2")
    }

    func testCodableRoundTrip() throws {
        var d = Deck.new(title: "Rund")
        d.slides.append(SlideLayout.titleAndText.makeSlide(theme: Theme.all[2]))
        d.slides[1].elements.append(Element(frame: Frame(x: 0, y: 0, w: 10, h: 10),
                                            content: .shape(ShapeBox(kind: .star, fill: .black)), link: .nextSlide))
        let back = try JSONDecoder().decode(Deck.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back, d)
    }

    func testHostAndTwoClientsConverge() async throws {
        let hostStore = tmpStore()
        let host = Session(deck: .new(title: "Delad"), me: Peer(name: "Pappa", color: Peer.palette[0]), assets: hostStore)
        try host.startHosting(advertise: false)
        try await waitUntil("värden lyssnar") { host.hostPort != nil }
        let port = NWEndpoint.Port(rawValue: host.hostPort!)!

        let aStore = tmpStore()
        let a = Session(deck: .new(title: "A:s egen"), me: Peer(name: "Ida", color: Peer.palette[0]), assets: aStore)
        let b = Session(deck: .new(title: "B:s egen"), me: Peer(name: "Leo", color: Peer.palette[1]), assets: tmpStore())
        let tv = Session(deck: .new(title: "tv"), me: Peer(name: "TV", color: Peer.palette[2], role: .stage), assets: tmpStore())
        let stranger = Session(deck: .new(title: "x"), me: Peer(name: "Okänd", color: Peer.palette[3]), assets: tmpStore())
        for s in [a, b, tv, stranger] { s.join(.hostPort(host: "127.0.0.1", port: port)) }
        // TV:n tittar bara och kommer in direkt; redigerare väntar på värdens ja.
        try await waitUntil("tv inne, redigerare väntar") { tv.link == .connected && host.joinRequests.count == 3 }
        XCTAssertEqual(a.link, .connecting)
        XCTAssertNotEqual(a.deck.title, "Delad", "ingen data före insläpp")
        host.answer(a.me.id, admit: true)
        host.answer(b.me.id, admit: true)
        host.answer(stranger.me.id, admit: false)
        try await waitUntil("alla anslutna") { [a, b, tv].allSatisfy { $0.link == .connected } && host.peers.count == 4 }
        try await waitUntil("den okände fick nej") { stranger.link == .lost("Pappa släppte inte in dig") }
        XCTAssertNotEqual(stranger.deck.title, "Delad")
        XCTAssertEqual(a.deck.title, "Delad")
        XCTAssertNotEqual(a.me.color, host.me.color, "krockande färg ska bytas")

        let slide = host.deck.slides[0].id
        // Samtidiga insättningar på samma plats från tre håll: alla måste hamna i samma ordning.
        a.perform(.insertSlide(Slide(notes: "a"), at: 1))
        b.perform(.insertSlide(Slide(notes: "b"), at: 1))
        host.perform(.insertSlide(Slide(notes: "h"), at: 1))
        let ea = text("från Ida")
        a.perform(.upsertElement(slide: slide, ea, at: nil))
        try await waitUntil("konvergens") {
            [a, b, tv].allSatisfy { $0.deck.slides == host.deck.slides } && host.deck.slides.count == 4
        }

        // Lås: Ida markerar sitt element, Leo får inte ändra det.
        a.select(ea.id)
        try await waitUntil("låset syns hos Leo") { b.isLockedByOther(ea.id)?.name == "Ida" }
        var hacked = ea; hacked.frame.x = 999
        XCTAssertFalse(b.perform(.upsertElement(slide: slide, hacked, at: nil)))
        // Även om Leo:s app skulle missa låset avvisar värden.
        b.select(nil)

        // Bild från en klient når TV:n.
        let png = try XCTUnwrap(Self.tinyPNG())
        let assetID = try aStore.importImage(png)
        a.perform(.upsertElement(slide: slide, Element(frame: Frame(x: 0, y: 0, w: 100, h: 100),
                                                         content: .image(ImageBox(assetID: assetID))), at: nil))
        try await waitUntil("bilden synkad till tv") { tv.assets.has(assetID) && hostStore.has(assetID) }

        // Ångra hos Ida går via värden till alla.
        a.undo()
        try await waitUntil("ångra synkad") { tv.deck.slides[0].elements.count == host.deck.slides[0].elements.count
            && host.deck.slides[0].elements.contains { $0.id == ea.id } && !host.deck.slides[0].assetIDs.contains(assetID) }

        // Fjärrkontrollen på TV:n styr presentationen hos alla.
        tv.remote(.start); tv.remote(.next)
        try await waitUntil("presentation") { a.present == PresentState(isPresenting: true, slideIndex: 1) }

        // Ida kopplar ner: hennes lås släpps.
        a.leave()
        try await waitUntil("lås släppt") { b.isLockedByOther(ea.id) == nil && host.peers.count == 3 }
        host.stopHosting()
        try await waitUntil("klienterna märker att värden slutat") { b.role == .solo && tv.role == .solo }
    }

    func testResumeAfterPauseAndReadmit() async throws {
        let host = Session(deck: .new(title: "Paus"), me: Peer(name: "Pappa", color: Peer.palette[0]), assets: tmpStore())
        try host.startHosting(advertise: false)
        try await waitUntil("lyssnar") { host.hostPort != nil }
        let port = NWEndpoint.Port(rawValue: host.hostPort!)!
        let me = Peer(name: "Ida", color: Peer.palette[1])
        let a = Session(deck: .new(title: "a"), me: me, assets: tmpStore())
        a.join(.hostPort(host: "127.0.0.1", port: port))
        try await waitUntil("frågar") { host.joinRequests.count == 1 }
        host.answer(me.id, admit: true)
        try await waitUntil("inne") { a.link == .connected }
        // iOS pausar värden: allt bryts. Värden startar om på samma port.
        a.leave()
        host.resumeHosting()
        try await waitUntil("lyssnar igen") { host.link == .connected && host.hostPort == port.rawValue }
        let again = Session(deck: .new(title: "a2"), me: me, assets: tmpStore())
        again.join(.hostPort(host: "127.0.0.1", port: port))
        try await waitUntil("inne direkt, utan ny fråga") { again.link == .connected }
        XCTAssertTrue(host.joinRequests.isEmpty)
        XCTAssertEqual(again.deck.title, "Paus")
        host.stopHosting()
    }

    static func tinyPNG() -> Data? {
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let out = NSMutableData()
        let dst = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dst, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dst)
        return out as Data
    }
}
