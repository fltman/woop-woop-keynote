import XCTest
import AVFoundation
@testable import SlideKit

/// "Visa när jag trycker" (klickanimationer i <p:timing>) och klickljud (<a:snd>, WAV) i .pptx.
/// Sätt WOOP_PPTX_BUILDS_OUT=/sökväg/fil.pptx för att spara provfilen och jämföra i Keynote/PowerPoint.
final class PPTXBuildTests: XCTestCase {

    /// En kort sinuston som .m4a (AAC), som en inspelning från telefonen.
    static func sineM4A(seconds: Double = 0.6, hz: Double = 660) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sine-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        try {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
            let n = AVAudioFrameCount(44100 * seconds)
            let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
            buf.frameLength = n
            let p = buf.floatChannelData![0]
            for i in 0..<Int(n) { p[i] = Float(sin(2 * .pi * hz * Double(i) / 44100) * 0.5) }
            try file.write(from: buf)
        }()
        return try Data(contentsOf: url)
    }

    static func buildDeck(assets: AssetStore) throws -> Deck {
        let snd = try assets.importAudio(sineM4A(), ext: "m4a")
        func box(_ t: String, _ x: Double, _ y: Double, _ c: String, reveal: AppearEffect?, sound: String? = nil) -> Element {
            Element(frame: Frame(x: x, y: y, w: 520, h: 300),
                    content: .shape(ShapeBox(kind: .roundedRectangle, fill: RGBA(hex: c))), reveal: reveal, sound: sound)
        }
        var s1 = Slide(background: .solid(RGBA(hex: "1B1464")))
        s1.elements = [
            Element(frame: Frame(x: 100, y: 40, w: 1720, h: 140),
                    content: .text(TextBox(text: "Fem effekter – klicka!", style: TextStyle(size: 96, color: .white, bold: true, align: .center)))),
            box("Tona", 120, 260, "FFC312", reveal: .fade),
            box("Poppa", 700, 260, "C4E538", reveal: .pop, sound: snd),
            box("Nerifrån", 1280, 260, "12CBC4", reveal: .flyUp),
            box("Vänster", 400, 680, "FDA7DF", reveal: .flyFromLeft),
            Element(frame: Frame(x: 1000, y: 680, w: 520, h: 300),
                    content: .text(TextBox(text: "Från höger", style: TextStyle(size: 96, color: RGBA(hex: "ED4C67"), bold: true))),
                    reveal: .flyFromRight),
        ]
        let s2id = UUID()
        // Bild 2: ljud vid klick, både ensamt och tillsammans med en länk.
        let s2 = Slide(id: s2id, background: .solid(.white), elements: [
            Element(frame: Frame(x: 200, y: 300, w: 600, h: 400),
                    content: .shape(ShapeBox(kind: .star, fill: RGBA(hex: "F79F1F"))), sound: snd),
            Element(frame: Frame(x: 1100, y: 400, w: 700, h: 200),
                    content: .text(TextBox(text: "Ljud + tillbaka", style: TextStyle(size: 80, align: .center))),
                    link: .previousSlide, sound: snd),
        ])
        return Deck(title: "Byggen och ljud", slides: [s1, s2])
    }

    func unzipped(_ deck: Deck, _ assets: AssetStore) throws -> URL {
        let data = try PPTXExporter.export(deck, assets: assets)
        if let out = ProcessInfo.processInfo.environment["WOOP_PPTX_BUILDS_OUT"] {
            try? FileManager.default.removeItem(atPath: out)
            try data.write(to: URL(fileURLWithPath: out))
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("builds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("b.pptx")
        try data.write(to: file)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-q", file.path, "-d", dir.appendingPathComponent("x").path]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        return dir.appendingPathComponent("x")
    }

    func testRevealTimingAndClickSounds() throws {
        let assets = AssetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("ba-\(UUID().uuidString)"))
        let deck = try Self.buildDeck(assets: assets)
        let x = try unzipped(deck, assets)

        // Alla XML-delar välformade.
        for u in FileManager.default.enumerator(at: x, includingPropertiesForKeys: nil)!.compactMap({ $0 as? URL })
            where ["xml", "rels"].contains(u.pathExtension) {
            let parser = XMLParser(contentsOf: u)!
            XCTAssertTrue(parser.parse(), "\(u.lastPathComponent): \(String(describing: parser.parserError))")
        }

        let s1 = try String(contentsOf: x.appendingPathComponent("ppt/slides/slide1.xml"), encoding: .utf8)
        // En klickgrupp per dolt element, i elementordning.
        XCTAssertEqual(s1.components(separatedBy: "nodeType=\"clickEffect\"").count - 1, 5)
        XCTAssertEqual(s1.components(separatedBy: "<p:cond delay=\"indefinite\"/>").count - 1, 5)
        let presets = matches(#"presetID="(\d+)" presetClass="entr" presetSubtype="(\d+)""#, in: s1)
        XCTAssertEqual(presets.map { "\($0[0])/\($0[1])" }, ["10/0", "53/16", "2/4", "2/8", "2/2"])
        // spid pekar på formerna i spTree (titeln = 2, de dolda 3…7).
        let spids = matches(#"<p:set><p:cBhvr><p:cTn [^>]*>.*?</p:cTn><p:tgtEl><p:spTgt spid="(\d+)"/>"#, in: s1).map { $0[0] }
        XCTAssertEqual(spids, ["3", "4", "5", "6", "7"])
        for id in spids { XCTAssertTrue(s1.contains("<p:cNvPr id=\"\(id)\""), "shape \(id) saknas") }
        XCTAssertFalse(s1.contains("spid=\"2\""), "titeln ska inte animeras")
        // Ingen form är dold i själva XML:en.
        XCTAssertFalse(s1.contains("hidden=\"1\""))
        // Ljud när "Poppa" visas.
        XCTAssertTrue(s1.contains("<p:sndTgt r:embed="))

        // Klickljud: WAV i media, audio-rel, <a:snd> i hlinkClick – även ihop med en länk.
        let media = try FileManager.default.contentsOfDirectory(atPath: x.appendingPathComponent("ppt/media").path)
        XCTAssertEqual(media.filter { $0.hasSuffix(".wav") }.count, 1, "\(media)")
        XCTAssertTrue(media.allSatisfy { !$0.hasSuffix(".m4a") }, "m4a hör inte hemma i .pptx")
        let wav = try Data(contentsOf: x.appendingPathComponent("ppt/media/\(media.first { $0.hasSuffix(".wav") }!)"))
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertGreaterThan(wav.count, 44100)   // ~0,6 s mono 16 bit

        let s2 = try String(contentsOf: x.appendingPathComponent("ppt/slides/slide2.xml"), encoding: .utf8)
        XCTAssertEqual(s2.components(separatedBy: "<a:snd r:embed=").count - 1, 2)
        XCTAssertTrue(s2.contains("action=\"ppaction://noaction\" highlightClick=\"1\"><a:snd"))
        XCTAssertTrue(s2.contains("jump=previousslide\"><a:snd"))
        XCTAssertFalse(s2.contains("<p:timing>"), "inga dolda element på bild 2")
        let r2 = try String(contentsOf: x.appendingPathComponent("ppt/slides/_rels/slide2.xml.rels"), encoding: .utf8)
        XCTAssertTrue(r2.contains("relationships/audio\" Target=\"../media/"))
        let ct = try String(contentsOf: x.appendingPathComponent("[Content_Types].xml"), encoding: .utf8)
        XCTAssertTrue(ct.contains("Extension=\"wav\" ContentType=\"audio/wav\""))
    }

    func matches(_ pattern: String, in s: String) -> [[String]] {
        let re = try! NSRegularExpression(pattern: pattern)
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m in
            (1..<m.numberOfRanges).map { String(s[Range(m.range(at: $0), in: s)!]) }
        }
    }
}
