import Foundation

/// Varje ändring av en presentation är en Op (CONTRACT §3).
/// Op:erna är idempotenta där det går, så att en dubblett aldrig förstör något.
public enum Op: Codable, Hashable, Sendable {
    case setTitle(String)
    case insertSlide(Slide, at: Int)
    case deleteSlide(UUID)
    case moveSlide(UUID, to: Int)
    /// Bakgrund, anteckningar och övergång. Elementen ändras med egna op:ar.
    case setSlideProps(UUID, background: Fill, notes: String, transition: DeckTransition)
    /// Lägg till eller ersätt. `at` gäller bara när elementet läggs till (nil = överst).
    case upsertElement(slide: UUID, Element, at: Int?)
    case deleteElement(slide: UUID, element: UUID)
    /// Lagerordning: 0 = längst bak.
    case moveElement(slide: UUID, element: UUID, to: Int)

    /// Elementet som op:en rör, om någon. Låsen kontrolleras mot det (CONTRACT §4).
    public var elementID: UUID? {
        switch self {
        case .upsertElement(_, let e, _): e.id
        case .deleteElement(_, let id), .moveElement(_, let id, _): id
        default: nil
        }
    }

    /// Bilden som op:en rör, så att TV:n kan följa den senast ändrade bilden.
    public var slideID: UUID? {
        switch self {
        case .setTitle: nil
        case .insertSlide(let s, _): s.id
        case .deleteSlide(let id), .moveSlide(let id, _), .setSlideProps(let id, _, _, _): id
        case .upsertElement(let id, _, _), .deleteElement(let id, _), .moveElement(let id, _, _): id
        }
    }
}

extension Deck {
    /// Tillämpar op:en. Returnerar false om den inte gick att tillämpa (t.ex. bilden finns inte),
    /// och då är decket oförändrat.
    @discardableResult
    public mutating func apply(_ op: Op) -> Bool {
        switch op {
        case .setTitle(let t):
            title = t
        case .insertSlide(let s, let at):
            guard slideIndex(s.id) == nil else { return false }
            slides.insert(s, at: min(max(at, 0), slides.count))
        case .deleteSlide(let id):
            guard let i = slideIndex(id) else { return false }
            slides.remove(at: i)
        case .moveSlide(let id, let to):
            guard let i = slideIndex(id) else { return false }
            let s = slides.remove(at: i)
            slides.insert(s, at: min(max(to, 0), slides.count))
        case .setSlideProps(let id, let bg, let notes, let tr):
            guard let i = slideIndex(id) else { return false }
            slides[i].background = bg; slides[i].notes = notes; slides[i].transition = tr
        case .upsertElement(let sid, let e, let at):
            guard let i = slideIndex(sid) else { return false }
            if let j = slides[i].elements.firstIndex(where: { $0.id == e.id }) {
                slides[i].elements[j] = e
            } else {
                let n = slides[i].elements.count
                slides[i].elements.insert(e, at: min(max(at ?? n, 0), n))
            }
        case .deleteElement(let sid, let eid):
            guard let i = slideIndex(sid), let j = slides[i].elements.firstIndex(where: { $0.id == eid }) else { return false }
            slides[i].elements.remove(at: j)
        case .moveElement(let sid, let eid, let to):
            guard let i = slideIndex(sid), let j = slides[i].elements.firstIndex(where: { $0.id == eid }) else { return false }
            let e = slides[i].elements.remove(at: j)
            slides[i].elements.insert(e, at: min(max(to, 0), slides[i].elements.count))
        }
        return true
    }

    /// Op:en som tar tillbaka `op`, räknad mot decket FÖRE tillämpningen. Används för ångra.
    public func inverse(of op: Op) -> Op? {
        switch op {
        case .setTitle:
            return .setTitle(title)
        case .insertSlide(let s, _):
            return .deleteSlide(s.id)
        case .deleteSlide(let id):
            guard let i = slideIndex(id) else { return nil }
            return .insertSlide(slides[i], at: i)
        case .moveSlide(let id, _):
            guard let i = slideIndex(id) else { return nil }
            return .moveSlide(id, to: i)
        case .setSlideProps(let id, _, _, _):
            guard let s = slide(id) else { return nil }
            return .setSlideProps(id, background: s.background, notes: s.notes, transition: s.transition)
        case .upsertElement(let sid, let e, _):
            guard let s = slide(sid) else { return nil }
            if let old = s.element(e.id) { return .upsertElement(slide: sid, old, at: nil) }
            return .deleteElement(slide: sid, element: e.id)
        case .deleteElement(let sid, let eid):
            guard let s = slide(sid), let j = s.elements.firstIndex(where: { $0.id == eid }) else { return nil }
            return .upsertElement(slide: sid, s.elements[j], at: j)
        case .moveElement(let sid, let eid, _):
            guard let s = slide(sid), let j = s.elements.firstIndex(where: { $0.id == eid }) else { return nil }
            return .moveElement(slide: sid, element: eid, to: j)
        }
    }
}
