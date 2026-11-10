#if DEBUG
import Foundation
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
                                   content: .shape(ShapeBox(kind: .triangle, fill: RGBA(hex: "FF4757")))))
        s2.elements.append(Element(frame: Frame(x: 1420, y: 330, w: 180, h: 180),
                                   content: .shape(ShapeBox(kind: .star, fill: RGBA(hex: "FFC312")))))
        deck.slides.append(s2)
        var s3 = SlideLayout.bigWord.makeSlide(theme: Theme.all[2])
        if case .text(var t) = s3.elements[0].content { t.text = "BOOM!"; s3.elements[0].content = .text(t) }
        s3.transition = .push
        deck.slides.append(s3)
        model.library.save(deck)
        model.open(deck)
        if ProcessInfo.processInfo.arguments.contains("-share") { try? model.session?.startHosting() }
        if ProcessInfo.processInfo.arguments.contains("-script"), let s = model.session {
            Task { await script(s) }
        }
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
