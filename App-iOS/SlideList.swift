import SwiftUI
import SlideKit

/// Bilderna i ordning. Lodrät på iPad, vågrät på iPhone. Visar var de andra är.
struct SlideList: View {
    let session: Session
    @Binding var current: UUID?
    var axis: Axis

    private var deck: Deck { session.deck }

    var body: some View {
        if axis == .vertical {
            List {
                ForEach(Array(deck.slides.enumerated()), id: \.element.id) { i, s in
                    row(i, s).listRowSeparator(.hidden)
                }
                .onMove { from, to in
                    guard let f = from.first else { return }
                    let id = deck.slides[f].id
                    session.perform(.moveSlide(id, to: to > f ? to - 1 : to))
                }
                addMenu.listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(deck.slides.enumerated()), id: \.element.id) { i, s in
                        row(i, s).frame(width: 140)
                    }
                    addMenu.frame(width: 80)
                }
                .padding(10)
            }
        }
    }

    private func row(_ i: Int, _ s: Slide) -> some View {
        let here = session.presence.values.filter { $0.slide == s.id && $0.peer != session.me.id }
            .compactMap { p in session.peers.first { $0.id == p.peer } }
        return HStack(alignment: .top, spacing: 6) {
            Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18)
            SlideView(slide: s, assets: session.assets, assetVersion: session.assetVersion)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(current == s.id ? Color.accentColor : .gray.opacity(0.3), lineWidth: current == s.id ? 3 : 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: -4) {
                        ForEach(here) { p in Circle().fill(p.color.color).frame(width: 14, height: 14)
                            .overlay { Circle().stroke(.white, lineWidth: 1.5) } }
                    }
                    .padding(4)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { current = s.id }
        .contextMenu {
            Button("Duplicera", systemImage: "plus.square.on.square") {
                var copy = s
                copy.id = UUID()
                copy.elements = s.elements.map { var e = $0; e.id = UUID(); return e }
                session.perform(.insertSlide(copy, at: i + 1))
                current = copy.id
            }
            Button("Ta bort", systemImage: "trash", role: .destructive) {
                guard deck.slides.count > 1 else { return }
                session.perform(.deleteSlide(s.id))
            }
            .disabled(deck.slides.count <= 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bild \(i + 1)")
        .accessibilityAddTraits(current == s.id ? [.isButton, .isSelected] : .isButton)
    }

    private var addMenu: some View {
        Menu {
            ForEach(SlideLayout.allCases) { l in
                Button(l.name) { add(l) }
            }
        } label: {
            Label("Ny bild", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func add(_ layout: SlideLayout) {
        let base = current.flatMap { deck.slide($0) } ?? deck.slides.last
        let theme = base.map { Theme.inferred(from: $0) } ?? Theme.all[0]
        let s = layout.makeSlide(theme: theme)
        let at = (current.flatMap { deck.slideIndex($0) } ?? deck.slides.count - 1) + 1
        if session.perform(.insertSlide(s, at: at)) { current = s.id }
    }
}
