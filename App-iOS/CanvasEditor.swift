import SwiftUI
import SlideKit

/// Bildytan i editorn: markera, flytta, ändra storlek och rotera.
/// Under ett drag ändras bara den lokala förhandsvisningen (och scenen får en DragPreview).
/// En op skickas först när fingret släpper.
struct CanvasEditor: View {
    let session: Session
    let slide: Slide
    @Binding var selection: UUID?
    var onEditText: (UUID) -> Void

    @State private var live: DragPreview?
    @State private var start: Element?
    @State private var guides: (v: Bool, h: Bool) = (false, false)
    @State private var lastPresence = Date.distantPast

    private var shown: Slide {
        guard let l = live, let i = slide.elements.firstIndex(where: { $0.id == l.element }) else { return slide }
        var s = slide
        s.elements[i].frame = l.frame
        s.elements[i].rotation = l.rotation
        return s
    }

    /// Andras markeringar och pågående drag på den här bilden.
    private var others: (marks: [UUID: Peer], drags: [UUID: DragPreview]) {
        var marks: [UUID: Peer] = [:]
        for (e, p) in session.locks where p != session.me.id {
            if let peer = session.peers.first(where: { $0.id == p }), slide.element(e) != nil { marks[e] = peer }
        }
        var drags: [UUID: DragPreview] = [:]
        for p in session.presence.values where p.peer != session.me.id && p.slide == slide.id {
            if let d = p.drag { drags[d.element] = d }
        }
        return (marks, drags)
    }

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / SlideSize.width
            let o = others
            ZStack(alignment: .topLeading) {
                SlideCanvas(slide: shown, assets: session.assets, drags: o.drags, marks: o.marks,
                            assetVersion: session.assetVersion)
                    .scaleEffect(k, anchor: .topLeading)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { selection = nil }

                ForEach(shown.elements) { e in hitArea(e, k) }

                if guides.v { Rectangle().fill(.pink).frame(width: 2, height: geo.size.height).offset(x: geo.size.width / 2 - 1) }
                if guides.h { Rectangle().fill(.pink).frame(width: geo.size.width, height: 2).offset(y: geo.size.height / 2 - 1) }

                if let id = selection, let e = shown.element(id), session.isLockedByOther(id) == nil {
                    Handles(element: e, k: k,
                            onResize: { corner, t in resize(e, corner: corner, t: t, k: k) },
                            onRotate: { loc in rotate(e, to: loc, k: k) },
                            onEnd: { commit() })
                }
            }
            .coordinateSpace(name: "canvas")
        }
        .aspectRatio(SlideSize.width / SlideSize.height, contentMode: .fit)
    }

    private func hitArea(_ e: Element, _ k: Double) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: max(e.frame.w * k, 24), height: max(e.frame.h * k, 24))
            .rotationEffect(.degrees(e.rotation))
            .position(x: e.frame.midX * k, y: e.frame.midY * k)
            .onTapGesture(count: 2) {
                guard session.isLockedByOther(e.id) == nil else { return }
                selection = e.id
                if case .text = e.content { onEditText(e.id) }
            }
            .onTapGesture {
                guard session.isLockedByOther(e.id) == nil else { return }
                selection = e.id
            }
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("canvas"))
                .onChanged { v in move(e, t: v.translation, k: k) }
                .onEnded { _ in commit() })
            .accessibilityElement()
            .accessibilityLabel(e.accessibilityName)
            .accessibilityAddTraits(.isButton)
    }

    // MARK: Gester

    private func begin(_ e: Element) -> Element? {
        guard session.isLockedByOther(e.id) == nil else { return nil }
        if start?.id != e.id {
            start = e
            selection = e.id
        }
        return start
    }

    private func move(_ e: Element, t: CGSize, k: Double) {
        guard let s = begin(e) else { return }
        var f = s.frame
        f.x += t.width / k
        f.y += t.height / k
        // Fäst mot bildens mitt.
        let snap = 14.0
        let v = abs(f.midX - SlideSize.width / 2) < snap
        let h = abs(f.midY - SlideSize.height / 2) < snap
        if v { f.x = SlideSize.width / 2 - f.w / 2 }
        if h { f.y = SlideSize.height / 2 - f.h / 2 }
        guides = (v, h)
        update(DragPreview(element: e.id, frame: f, rotation: s.rotation))
    }

    /// Hörnet (sx, sy) ∈ {-1, 1}² dras; motsatt hörn står still, även när elementet är roterat.
    private func resize(_ e: Element, corner: (Double, Double), t: CGSize, k: Double) {
        guard let s = begin(e) else { return }
        let f0 = s.frame
        let th = s.rotation * .pi / 180
        // Draget i elementets egna axlar.
        let dx = (t.width * cos(th) + t.height * sin(th)) / k
        let dy = (-t.width * sin(th) + t.height * cos(th)) / k
        let (sx, sy) = corner
        var w = f0.w + sx * dx, h = f0.h + sy * dy
        if case .image = s.content {
            // Bilder behåller proportionerna.
            let scale = 1 + (sx * dx * f0.w + sy * dy * f0.h) / (f0.w * f0.w + f0.h * f0.h)
            w = f0.w * scale; h = f0.h * scale
        }
        w = max(w, 40); h = max(h, 40)
        let lx = sx * (w - f0.w) / 2, ly = sy * (h - f0.h) / 2
        let cx = f0.midX + lx * cos(th) - ly * sin(th)
        let cy = f0.midY + lx * sin(th) + ly * cos(th)
        update(DragPreview(element: e.id, frame: Frame(x: cx - w / 2, y: cy - h / 2, w: w, h: h), rotation: s.rotation))
    }

    private func rotate(_ e: Element, to loc: CGPoint, k: Double) {
        guard let s = begin(e) else { return }
        let f = live?.frame ?? s.frame
        var deg = atan2(loc.y - f.midY * k, loc.x - f.midX * k) * 180 / .pi + 90
        // Fäst mot raka vinklar.
        for r in stride(from: -360.0, through: 360, by: 90) where abs(deg - r) < 6 { deg = r }
        deg = deg.truncatingRemainder(dividingBy: 360)
        update(DragPreview(element: e.id, frame: f, rotation: deg))
    }

    private func update(_ d: DragPreview) {
        live = d
        // Scenen får rörelsen live, men högst 30 gånger i sekunden.
        if Date().timeIntervalSince(lastPresence) > 1 / 30 {
            lastPresence = Date()
            session.setPresence(slide: slide.id, drag: d)
        }
    }

    private func commit() {
        defer { live = nil; start = nil; guides = (false, false); session.setPresence(slide: slide.id) }
        guard let l = live, var e = slide.element(l.element) else { return }
        guard e.frame != l.frame || e.rotation != l.rotation else { return }
        e.frame = l.frame
        e.rotation = l.rotation
        session.perform(.upsertElement(slide: slide.id, e, at: nil))
    }
}

/// Markeringsram med fyra hörn för storlek och en knopp för rotation.
private struct Handles: View {
    let element: Element
    let k: Double
    var onResize: ((Double, Double), CGSize) -> Void
    var onRotate: (CGPoint) -> Void
    var onEnd: () -> Void

    var body: some View {
        let w = element.frame.w * k, h = element.frame.h * k
        ZStack {
            Rectangle().stroke(Color.accentColor, lineWidth: 2).allowsHitTesting(false)
            ForEach(0..<4, id: \.self) { i in
                let c = (i % 2 == 0 ? -1.0 : 1.0, i < 2 ? -1.0 : 1.0)
                Circle().fill(.white).overlay { Circle().stroke(Color.accentColor, lineWidth: 2) }
                    .frame(width: 22, height: 22)
                    .padding(11).contentShape(Rectangle())
                    .offset(x: c.0 * w / 2, y: c.1 * h / 2)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                        .onChanged { v in onResize(c, v.translation) }
                        .onEnded { _ in onEnd() })
                    .accessibilityLabel("Ändra storlek")
            }
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Color.accentColor, in: Circle())
                .padding(8).contentShape(Rectangle())
                .offset(y: -h / 2 - 40)
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                    .onChanged { v in onRotate(v.location) }
                    .onEnded { _ in onEnd() })
                .accessibilityLabel("Rotera")
        }
        .frame(width: w, height: h)
        .rotationEffect(.degrees(element.rotation))
        .position(x: element.frame.midX * k, y: element.frame.midY * k)
    }
}

extension Element {
    var accessibilityName: String {
        switch content {
        case .text(let t): "Text: \(t.text)"
        case .shape(let s): s.kind.name
        case .image: "Bild"
        }
    }
}
