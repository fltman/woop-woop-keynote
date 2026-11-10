import Foundation

/// En rad i scenens händelseflöde: "Ida lade till en stjärna på bild 2".
public struct Activity: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var peer: UUID
    public var slide: UUID?
    public var text: String
    public var at: Date
    /// Samma person + samma nyckel inom kort tid uppdaterar raden i stället för att lägga till en ny
    /// (annars blir varje bokstav en egen rad).
    var key: String
}

/// Senaste ändringen av ett element, så att scenen kan låta det lysa upp en kort stund.
public struct RecentEdit: Equatable, Sendable {
    public var peer: UUID
    public var at: Date
}

extension Activity {
    /// Beskriver en op i klartext, räknat mot decket FÖRE op:en. nil = inget att visa.
    /// Anteckningar nämns aldrig: de är privata och syns aldrig på scenen.
    static func describe(_ op: Op, before d: Deck, name n: String) -> (text: String, key: String)? {
        func num(_ id: UUID) -> String { d.slideIndex(id).map { "bild \($0 + 1)" } ?? "en bild" }
        switch op {
        case .setTitle(let t):
            return ("\(n) döpte presentationen till »\(t)«", "title")
        case .insertSlide(_, let at):
            return ("\(n) lade till bild \(min(max(at, 0), d.slides.count) + 1)", "ins-\(at)")
        case .deleteSlide(let id):
            return ("\(n) tog bort \(num(id))", "del-\(id)")
        case .moveSlide(let id, let to):
            return ("\(n) flyttade \(num(id)) till plats \(to + 1)", "mv-\(id)")
        case .setSlideProps(let id, let bg, _, let tr):
            guard let s = d.slide(id) else { return nil }
            if s.background != bg { return ("\(n) ändrade bakgrunden på \(num(id))", "bg-\(id)") }
            if s.transition != tr { return ("\(n) valde övergången \(tr.name.lowercased()) till \(num(id))", "tr-\(id)") }
            return nil
        case .upsertElement(let sid, let e, _):
            let (a, the) = e.content.forms
            guard let old = d.slide(sid)?.element(e.id) else { return ("\(n) lade till \(a) på \(num(sid))", "add-\(e.id)") }
            if case .text(let t) = e.content, case .text(let o) = old.content, t.text != o.text {
                return ("\(n) skriver: »\(snippet(t.text))«", "type-\(e.id)")
            }
            if old.frame.w != e.frame.w || old.frame.h != e.frame.h {
                return ("\(n) ändrade storlek på \(the)", "size-\(e.id)")
            }
            if old.frame != e.frame { return ("\(n) flyttade \(the)", "move-\(e.id)") }
            if old.rotation != e.rotation { return ("\(n) vred på \(the)", "rot-\(e.id)") }
            if old.link != e.link, e.link != nil { return ("\(n) gjorde \(the) klickbar", "link-\(e.id)") }
            return ("\(n) ändrade \(the)", "style-\(e.id)")
        case .deleteElement(let sid, let eid):
            guard let old = d.slide(sid)?.element(eid) else { return nil }
            return ("\(n) tog bort \(old.content.forms.1)", "rm-\(eid)")
        case .moveElement(let sid, let eid, let to):
            guard let old = d.slide(sid)?.element(eid) else { return nil }
            return ("\(n) lade \(old.content.forms.1) \(to == 0 ? "längst bak" : "längst fram")", "z-\(eid)")
        }
    }

    /// Slutet av texten (där man skriver), på en rad.
    static func snippet(_ s: String) -> String {
        let line = s.replacingOccurrences(of: "\n", with: " ")
        return line.count > 36 ? "…" + line.suffix(36) : line
    }
}
