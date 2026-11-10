#if DEBUG
import UIKit
import SlideKit

/// Startflaggan -demo: ett färdigt deck som delas direkt. Bara för att prova på simulatorn.
@MainActor
enum Demo {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static func run(_ model: AppModel) {
        if model.profile.name.isEmpty { model.profile.name = "Ida" }
        var deck = Deck.new(title: "Vulkaner", theme: Theme.all[0])
        if case .text(var t) = deck.slides[0].elements[1].content {
            t.text = "av Ida, Leo och Mio"
            deck.slides[0].elements[1].content = .text(t)
        }
        var s2 = SlideLayout.titleAndText.makeSlide(theme: Theme.all[0])
        if case .text(var t) = s2.elements[0].content { t.text = "Tre sorters vulkaner"; s2.elements[0].content = .text(t) }
        if case .text(var t) = s2.elements[1].content {
            t.text = "• Sköldvulkaner\n• Stratovulkaner\n• Kalderor"; s2.elements[1].content = .text(t)
        }
        s2.elements.append(Element(frame: Frame(x: 1300, y: 420, w: 420, h: 380), rotation: -8,
                                   content: .shape(ShapeBox(kind: .triangle, fill: RGBA(hex: "FF4757"))), reveal: .flyUp))
        s2.elements.append(Element(frame: Frame(x: 1420, y: 330, w: 180, h: 180),
                                   content: .shape(ShapeBox(kind: .star, fill: RGBA(hex: "FFC312"))), reveal: .pop))
        s2.notes = "Börja med att fråga om någon har sett en vulkan.\nSköldvulkaner är platta, stratovulkaner är spetsiga.\nTryck fram triangeln och stjärnan."
        deck.slides.append(s2)
        var s3 = SlideLayout.bigWord.makeSlide(theme: Theme.all[2])
        if case .text(var t) = s3.elements[0].content { t.text = "BOOM!"; s3.elements[0].content = .text(t) }
        s3.transition = .push
        deck.slides.append(s3)
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

    /// Startflaggan -script: "spelar Ida" så att scenen har något att följa.
    static func script(_ s: Session) async {
        func wait(_ t: Double) async { try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000)) }
        await wait(8)
        guard s.deck.slides.count > 1 else { return }
        let slide = s.deck.slides[1].id
        s.setPresence(slide: slide)
        await wait(1.5)
        let star = Element(frame: Frame(x: 1500, y: 120, w: 260, h: 260),
                           content: .shape(ShapeBox(kind: .heart, fill: RGBA(hex: "FF6B81"))))
        s.perform(.upsertElement(slide: slide, star, at: nil))
        await wait(1.5)
        var note = Element(frame: Frame(x: 120, y: 760, w: 1100, h: 120),
                           content: .text(TextBox(text: "", style: TextStyle(font: .trebuchet, size: 64, color: RGBA(hex: "FFC312"), bold: true))))
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
