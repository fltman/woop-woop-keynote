import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SlideKit

final class PPTXTests: XCTestCase {

    /// Exempeldeck med alla elementtyper. Används också för att jämföra mot Keynote och PowerPoint
    /// (sätt WOOP_PPTX_OUT=/sökväg/fil.pptx för att spara filen).
    static func sampleDeck(assets: AssetStore) throws -> Deck {
        let png = try makePNG(width: 400, height: 300)
        let imgID = try assets.importImage(png)
        let bgPNG = try makePNG(width: 320, height: 180, gradient: true)
        let bgID = try assets.importImage(bgPNG)

        func text(_ t: String, _ f: Frame, align: TextAlign, size: Double = 64, font: FontFamily = .arial,
                  color: RGBA = .black, bold: Bool = false, italic: Bool = false, rot: Double = 0) -> Element {
            Element(frame: f, rotation: rot, content: .text(TextBox(text: t, style: TextStyle(
                font: font, size: size, color: color, bold: bold, italic: italic, align: align))))
        }

        // Bild 1: texter, solid bakgrund.
        let s1 = Slide(background: .solid(RGBA(hex: "FBF7EF")), elements: [
            text("Vänster & <rad 1>\nrad två \"citat\"", Frame(x: 100, y: 100, w: 800, h: 200), align: .leading, font: .georgia),
            text("Mitten\nfet", Frame(x: 560, y: 400, w: 800, h: 200), align: .center, font: .verdana, color: RGBA(hex: "D63031"), bold: true),
            text("Höger\nkursiv", Frame(x: 1020, y: 700, w: 800, h: 200), align: .trailing, font: .times, italic: true),
            text("Roterad 15°", Frame(x: 1100, y: 120, w: 600, h: 100), align: .center, size: 56, font: .trebuchet, rot: 15),
            Element(frame: Frame(x: 0, y: 0, w: 1920, h: 20), content: .shape(ShapeBox(kind: .rectangle, fill: RGBA(hex: "0984E3")))),
        ], notes: "Säg hej till publiken!\nAndra raden.", transition: .fade)

        // Bild 2: alla sju former, gradientbakgrund.
        var shapes: [Element] = []
        for (i, k) in ShapeKind.allCases.enumerated() {
            let col = i % 4, row = i / 4
            shapes.append(Element(frame: Frame(x: 120 + Double(col) * 440, y: 160 + Double(row) * 440, w: 360, h: 320),
                                  rotation: k == .arrow ? 30 : 0,
                                  content: .shape(ShapeBox(kind: k, fill: RGBA(hex: ["FFC312", "C4E538", "12CBC4", "FDA7DF", "ED4C67", "F79F1F", "A3CB38"][i]),
                                                           stroke: i % 2 == 0 ? .white : nil, strokeWidth: i % 2 == 0 ? 8 : 0))))
        }
        let s2 = Slide(background: .gradient(from: RGBA(hex: "1B1464"), to: RGBA(hex: "6F1E51"), angle: 90),
                       elements: shapes, transition: .push)

        // Bild 3: bild, länk, bildbakgrund.
        let s3id = UUID()
        let s3 = Slide(id: s3id, background: .image(assetID: bgID), elements: [
            Element(frame: Frame(x: 160, y: 240, w: 800, h: 600), content: .image(ImageBox(assetID: imgID))),
            text("Klicka → bild 1", Frame(x: 1100, y: 440, w: 700, h: 120), align: .center, size: 72, color: .white, bold: true),
        ], transition: .wipe)

        var deck = Deck(title: "Provdeck — Woop & Woop", slides: [s1, s2, s3])
        deck.slides[2].elements[1].link = .slide(s1.id)
        deck.slides[2].elements[0].link = .slide(s1.id)
        deck.slides[0].elements[3].link = .nextSlide
        deck.slides[1].elements[0].link = .url(URL(string: "https://example.com/?a=1&b=2")!)
        return deck
    }

    static func makePNG(width: Int, height: Int, gradient: Bool = false) throws -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if gradient {
            let g = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0, green: 0.4, blue: 0.2, alpha: 1),
                                                         CGColor(red: 0.1, green: 0.8, blue: 0.9, alpha: 1)] as CFArray,
                               locations: [0, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: width, y: height), options: [])
        } else {
            ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(CGColor(red: 0.85, green: 0.1, blue: 0.3, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
            ctx.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
            ctx.fill(CGRect(x: 0, y: height - 40, width: width, height: 40)) // blått band upptill (CG-origo nere)
        }
        let img = ctx.makeImage()!
        let out = NSMutableData()
        let dst = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dst, img, nil)
        CGImageDestinationFinalize(dst)
        return out as Data
    }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pptx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @discardableResult
    func run(_ exe: String, _ args: [String]) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, out)
    }

    func exportSample() throws -> (URL, Deck, URL) {
        let dir = try tempDir()
        let assets = AssetStore(directory: dir.appendingPathComponent("assets"))
        let deck = try Self.sampleDeck(assets: assets)
        let data = try PPTXExporter.export(deck, assets: assets)
        let file = dir.appendingPathComponent("prov.pptx")
        try data.write(to: file)
        if let out = ProcessInfo.processInfo.environment["WOOP_PPTX_OUT"] {
            try? FileManager.default.removeItem(atPath: out)
            try data.write(to: URL(fileURLWithPath: out))
        }
        return (file, deck, dir)
    }

    func testZipIsValid() throws {
        let (file, _, _) = try exportSample()
        let (status, out) = try run("/usr/bin/unzip", ["-t", file.path])
        XCTAssertEqual(status, 0, out)
        XCTAssertTrue(out.contains("No errors detected"), out)
    }

    func testAllXMLWellFormedAndMediaCount() throws {
        let (file, deck, dir) = try exportSample()
        let ex = dir.appendingPathComponent("x")
        let (status, out) = try run("/usr/bin/unzip", ["-q", file.path, "-d", ex.path])
        XCTAssertEqual(status, 0, out)

        let fm = FileManager.default
        let all = fm.enumerator(at: ex, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }
        let xmls = all.filter { ["xml", "rels"].contains($0.pathExtension) }
        XCTAssertGreaterThan(xmls.count, 10)
        for x in xmls {
            let parser = XMLParser(contentsOf: x)!
            XCTAssertTrue(parser.parse(), "\(x.lastPathComponent): \(String(describing: parser.parserError))")
        }
        let media = all.filter { $0.path.contains("/ppt/media/") }
        XCTAssertEqual(media.count, deck.assetIDs.count)
        XCTAssertEqual(media.count, 2)
        let slides = all.filter { $0.path.contains("/ppt/slides/slide") && $0.pathExtension == "xml" }
        XCTAssertEqual(slides.count, 3)
        XCTAssertTrue(fm.fileExists(atPath: ex.appendingPathComponent("ppt/notesSlides/notesSlide1.xml").path))
        XCTAssertFalse(fm.fileExists(atPath: ex.appendingPathComponent("ppt/notesSlides/notesSlide2.xml").path))

        let s1 = try String(contentsOf: ex.appendingPathComponent("ppt/slides/slide1.xml"), encoding: .utf8)
        XCTAssertTrue(s1.contains("Vänster &amp; &lt;rad 1&gt;"))
        XCTAssertTrue(s1.contains("rot=\"900000\""))
        XCTAssertTrue(s1.contains("sz=\"3200\""))           // 64 enheter = 32 pt
        XCTAssertTrue(s1.contains("<a:off x=\"635000\" y=\"635000\"/>")) // 100 enheter
        XCTAssertTrue(s1.contains("jump=nextslide"))
        XCTAssertTrue(s1.contains("<p:fade/>"))
        let r3 = try String(contentsOf: ex.appendingPathComponent("ppt/slides/_rels/slide3.xml.rels"), encoding: .utf8)
        XCTAssertTrue(r3.contains("Target=\"slide1.xml\""))
    }

    func testEmptyDeckAndEscaping() throws {
        let dir = try tempDir()
        let assets = AssetStore(directory: dir)
        let data = try PPTXExporter.export(Deck(title: "Tom \u{0001}<>"), assets: assets)
        let file = dir.appendingPathComponent("tom.pptx")
        try data.write(to: file)
        XCTAssertEqual(try run("/usr/bin/unzip", ["-t", file.path]).0, 0)
        XCTAssertEqual(PPTXExporter.esc("a\u{0001}b&"), "ab&amp;")
    }

    /// Renderar appens egen version av provdecket bredvid Keynotes/PowerPoints export
    /// (bara när WOOP_APP_PNG_DIR är satt).
    @MainActor
    func testRenderAppVersionForComparison() throws {
        guard let outDir = ProcessInfo.processInfo.environment["WOOP_APP_PNG_DIR"] else { return }
        let dir = try tempDir()
        let assets = AssetStore(directory: dir)
        let deck = try Self.sampleDeck(assets: assets)
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        for (i, slide) in deck.slides.enumerated() {
            let img = try XCTUnwrap(Snapshot.image(slide, assets: assets, width: 960))
            let url = URL(fileURLWithPath: outDir).appendingPathComponent("app.\(String(format: "%03d", i + 1)).png")
            let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dst, img, nil)
            XCTAssertTrue(CGImageDestinationFinalize(dst))
        }
    }

    func testCRC32KnownValue() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    /// Alla teman, layouter och upplägg ger bilder som håller sig på ytan och går att exportera.
    func testEveryThemeLayoutAndTemplateExports() throws {
        let store = AssetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("tpl-\(UUID())"))
        XCTAssertEqual(Set(Theme.all.map(\.id)).count, Theme.all.count, "tema-id:n ska vara unika")
        XCTAssertEqual(Theme.all.last?.id, "ren", "Theme.inferred utgår från det sista temat")
        for theme in Theme.all {
            var deck = Deck(title: theme.name, slides: SlideLayout.allCases.map { $0.makeSlide(theme: theme) })
            for t in DeckTemplate.allCases { deck.slides += t.makeDeck(theme: theme).slides }
            for s in deck.slides { for e in s.elements {
                XCTAssertTrue(e.frame.x >= 0 && e.frame.y >= 0 && e.frame.x + e.frame.w <= SlideSize.width
                              && e.frame.y + e.frame.h <= SlideSize.height, "\(theme.id): element utanför bilden \(e.frame)")
            } }
            XCTAssertGreaterThan(try PPTXExporter.export(deck, assets: store).count, 10_000, theme.id)
        }
        // Bildplatser är inga bilder: de begär ingen fil och hamnar inte i exporten.
        let ph = SlideLayout.threePictures.makeSlide(theme: Theme.all[0])
        XCTAssertEqual(ph.elements.filter(\.isImagePlaceholder).count, 3)
        XCTAssertTrue(ph.assetIDs.isEmpty)
        // Filnamnen står i klartext i zip-filen.
        let zip = try PPTXExporter.export(Deck(title: "p", slides: [ph]), assets: store)
        XCTAssertNil(zip.range(of: Data("ppt/media/".utf8)), "en bildplats ska inte bli en fil i .pptx")
        XCTAssertEqual(DeckTemplate.quiz.makeDeck(theme: Theme.all[0]).slides.filter { $0.elements.contains { $0.isQuiz } }.count, 3)
    }
}
