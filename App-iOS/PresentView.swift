import SwiftUI
import SlideKit

/// Presentation på iPaden. Med AirPlay-spegling hamnar den på TV:n.
/// Läget delas: är vi uppkopplade följer TV:n och de andra med.
struct PresentView: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var chrome = true

    private var index: Int { session.present.slideIndex }

    var body: some View {
        PresentationView(deck: session.deck, index: index, assets: session.assets,
                         assetVersion: session.assetVersion, onLink: follow)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.width < -40 { go(index + 1) } else if v.translation.width > 40 { go(index - 1) }
            })
            .onTapGesture(coordinateSpace: .global) { p in
                // Höger del = nästa, vänster = förra.
                let w = UIScreen.main.bounds.width
                go(p.x > w * 0.3 ? index + 1 : index - 1)
                chrome = false
            }
            .overlay(alignment: .topLeading) {
                HStack {
                    Button { stop() } label: {
                        Image(systemName: "xmark").font(.title2.bold()).padding(14)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Sluta presentera")
                    Text("\(index + 1) / \(session.deck.slides.count)")
                        .font(.headline.monospacedDigit()).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding()
                .opacity(chrome ? 1 : 0.15)
            }
            .overlay(alignment: .bottom) {
                let notes = session.deck.slides.indices.contains(index) ? session.deck.slides[index].notes : ""
                if chrome && !notes.isEmpty {
                    Text(notes).font(.body).padding().frame(maxWidth: 700)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
                }
            }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .onChange(of: session.present.isPresenting) { _, on in if !on { dismiss() } }
    }

    private func go(_ i: Int) {
        let n = session.deck.slides.count
        guard i >= 0, i < n else { return }
        session.setPresent(PresentState(isPresenting: true, slideIndex: i))
    }

    private func follow(_ link: ElementLink) {
        if case .url(let u) = link { openURL(u); return }
        if let t = session.deck.target(of: link, from: index) { go(t) }
    }

    private func stop() {
        session.setPresent(PresentState(isPresenting: false, slideIndex: index))
        dismiss()
    }
}
