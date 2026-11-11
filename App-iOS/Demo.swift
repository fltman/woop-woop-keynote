#if DEBUG
import UIKit
import SlideKit

/// Startflaggan -demo: ett färdigt deck som delas direkt. Bara för att prova på simulatorn.
@MainActor
enum Demo {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static func run(_ model: AppModel) {
        // Demot har alltid samma påhittade person, oavsett vem som är inloggad på simulatorn.
        model.profile.name = "Alex"
        let deck = makeDeck(model.library.assets)
        model.library.save(deck)
        model.open(deck)
        if ProcessInfo.processInfo.arguments.contains("-seedpaste") { seedPasteboard() }
        if ProcessInfo.processInfo.arguments.contains("-share") { try? model.session?.startHosting() }
        if ProcessInfo.processInfo.arguments.contains("-presentscript"), let s = model.session {
            Task {
                // Presenterar bild 2 och trycker "nästa": triangeln flyger in, sedan poppar stjärnan.
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                s.setPresent(PresentState(isPresenting: true, slideIndex: 1))
                for _ in 0..<3 {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    s.remote(.next)
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-script"), let s = model.session {
            Task { await script(s) }
        }
    }

    /// Demopresentationen. Med -demoimages <mapp> (bg.png och cut.png) får den riktiga bilder.
    static func makeDeck(_ assets: AssetStore) -> Deck {
        let args = ProcessInfo.processInfo.arguments
        func image(_ name: String) -> String? {
            guard let i = args.firstIndex(of: "-demoimages"), i + 1 < args.count,
                  let d = try? Data(contentsOf: URL(fileURLWithPath: args[i + 1]).appendingPathComponent(name)) else { return nil }
            return try? assets.importImage(d)
        }
        let navy = RGBA(hex: "0F1226"), gold = RGBA(hex: "FFC312"), soft = RGBA(hex: "E6E8F5")
        func text(_ t: String, _ size: Double, _ f: Frame, color: RGBA = .white, bold: Bool = false, align: TextAlign = .leading) -> Element {
            Element(frame: f, content: .text(TextBox(text: t, style: TextStyle(font: .trebuchet, size: size, color: color, bold: bold, align: align))))
        }

        var s1 = Slide(background: image("bg.png").map { .image(assetID: $0) } ?? Theme.all[0].background)
        s1.elements = [text("Vulkaner", 190, Frame(x: 110, y: 90, w: 1100, h: 240), bold: true),
                       text("av Alex, Sam och Kim", 60, Frame(x: 118, y: 330, w: 1100, h: 90), color: soft)]

        var s2 = Slide(background: .solid(navy), transition: .fade)
        s2.elements = [text("Så är en vulkan uppbyggd", 96, Frame(x: 110, y: 80, w: 1700, h: 140), bold: true),
                       text("• Magmakammaren ligger djupt under berget\n• Magman stiger genom en kanal\n• Aska och lava bygger lager på lager",
                            54, Frame(x: 110, y: 290, w: 860, h: 420), color: soft)]
        if let cut = image("cut.png") {
            s2.elements.append(Element(frame: Frame(x: 1030, y: 250, w: 780, h: 585), content: .image(ImageBox(assetID: cut)), reveal: .pop))
        } else {
            s2.elements.append(Element(frame: Frame(x: 1300, y: 420, w: 420, h: 380), rotation: -8,
                                       content: .shape(ShapeBox(kind: .triangle, fill: RGBA(hex: "FF4757"))), reveal: .flyUp))
        }
        s2.elements.append(text("Varmast: 1 200 grader", 60, Frame(x: 110, y: 760, w: 860, h: 100), color: gold, bold: true))
        s2.elements[s2.elements.count - 1].reveal = .flyFromLeft
        s2.notes = "Börja med att fråga om någon har sett en vulkan.\nPeka på magmakammaren i bilden.\nTryck fram bilden först, sedan temperaturen."

        var s3 = Slide(background: .solid(navy), transition: .push)
        s3.elements = [text("Tre kända vulkaner", 96, Frame(x: 110, y: 80, w: 1700, h: 140), bold: true),
                       Element(frame: Frame(x: 110, y: 250, w: 1100, h: 720),
                               content: .chart(ChartBox(kind: .bar, title: "Höjd över havet, meter", labels: ["Etna", "Hekla", "Vesuvius"],
                                                        values: [3357, 1491, 1281], accent: gold, textColor: soft))),
                       Element(frame: Frame(x: 1380, y: 330, w: 400, h: 400), content: .timer(TimerBox(seconds: 30, color: gold)))]
        s3.notes = "Etna är högst i Europa. Starta klockan och låt publiken gissa vilken som haft flest utbrott."

        var s4 = Slide(background: .solid(navy), transition: .zoom)
        s4.elements = [Element(frame: Frame(x: 210, y: 190, w: 1500, h: 700),
                               content: .poll(PollBox(question: "Vilken av dem är högst?", options: ["Etna", "Hekla", "Vesuvius"], correct: 0,
                                                      accent: gold, textColor: soft)))]

        var s5 = Slide(background: image("bg.png").map { .image(assetID: $0) } ?? Theme.all[0].background, transition: .fade)
        s5.elements = [text("Tack!", 260, Frame(x: 110, y: 120, w: 1200, h: 330), bold: true),
                       text("Har ni några frågor?", 70, Frame(x: 118, y: 450, w: 1200, h: 100), color: soft)]
        return Deck(title: "Vulkaner", slides: [s1, s2, s3, s4, s5])
    }

    /// Startflaggan -seedpaste: urklippet ser ut som när man väljer "Kopiera" på en bild i Safari:
    /// bilden (här WebP, som många sajter använder) och dess adress.
    static func seedPasteboard() {
        let size = CGSize(width: 640, height: 400)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemOrange.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 220, y: 100, width: 200, height: 200))
        }
        let out = NSMutableData()
        let webp = CGImageDestinationCreateWithData(out, "org.webmproject.webp" as CFString, 1, nil)
        let data: Data
        let type: String
        if let webp { CGImageDestinationAddImage(webp, img.cgImage!, nil) }
        if let webp, CGImageDestinationFinalize(webp) { data = out as Data; type = "org.webmproject.webp" }
        else { data = img.pngData()!; type = "public.png" }
        UIPasteboard.general.items = [[type: data, "public.url": URL(string: "https://example.com/vulkan.webp")!]]
        print("SEEDPASTE", type, data.count)
    }

    /// Startflaggan -script: "spelar Alex" så att scenen har något att följa.
    static func script(_ s: Session) async {
        func wait(_ t: Double) async { try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000)) }
        await wait(8)
        guard s.deck.slides.count > 1 else { return }
        let slide = s.deck.slides[1].id
        s.setPresence(slide: slide)
        await wait(1.5)
        let star = Element(frame: Frame(x: 1660, y: 60, w: 170, h: 170),
                           content: .shape(ShapeBox(kind: .heart, fill: RGBA(hex: "FF6B81"))))
        s.perform(.upsertElement(slide: slide, star, at: nil))
        await wait(1.5)
        var note = Element(frame: Frame(x: 110, y: 900, w: 1300, h: 110),
                           content: .text(TextBox(text: "", style: TextStyle(font: .trebuchet, size: 56, color: RGBA(hex: "FF6B81"), bold: true))))
        s.select(note.id)
        s.perform(.upsertElement(slide: slide, note, at: nil))
        for ch in "Den största är Olympus Mons!" {
            if case .text(var t) = note.content { t.text.append(ch); note.content = .text(t) }
            s.perform(.upsertElement(slide: slide, note, at: nil), coalesce: "type")
            await wait(0.12)
        }
    }
}
#endif
