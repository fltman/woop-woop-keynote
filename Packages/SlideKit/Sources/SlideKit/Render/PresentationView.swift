import SwiftUI

/// Helskärmspresentation, samma på iPad och Apple TV.
/// Bildbytet animeras med målbildens övergång.
public struct PresentationView: View {
    public var deck: Deck
    public var index: Int
    public var assets: AssetStore
    public var assetVersion: Int
    /// Tryck på ett element med länk (bara på enheter med pekskärm).
    public var onLink: ((ElementLink) -> Void)?

    @State private var shown: Int
    @State private var forward = true

    public init(deck: Deck, index: Int, assets: AssetStore, assetVersion: Int = 0, onLink: ((ElementLink) -> Void)? = nil) {
        self.deck = deck; self.index = index; self.assets = assets
        self.assetVersion = assetVersion; self.onLink = onLink
        _shown = State(initialValue: index)
    }

    public var body: some View {
        ZStack {
            Color.black
            if deck.slides.indices.contains(shown) {
                let slide = deck.slides[shown]
                SlideView(slide: slide, assets: assets, assetVersion: assetVersion)
                    .overlay { if let onLink { LinkTargets(slide: slide, onLink: onLink) } }
                    .id(slide.id)
                    .transition(Self.transition(slide.transition, forward: forward))
            }
        }
        .ignoresSafeArea()
        .onChange(of: index) { old, new in
            forward = new >= old
            let tr = deck.slides.indices.contains(new) ? deck.slides[new].transition : .none
            if tr == .none { shown = new } else { withAnimation(.easeInOut(duration: 0.5)) { shown = new } }
        }
    }

    static func transition(_ t: DeckTransition, forward: Bool) -> AnyTransition {
        switch t {
        case .none: .identity
        case .fade: .opacity
        case .push: .asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                removal: .move(edge: forward ? .leading : .trailing))
        case .wipe: .asymmetric(insertion: .move(edge: forward ? .trailing : .leading), removal: .identity)
        }
    }
}

/// Osynliga tryckytor över element som har en länk.
struct LinkTargets: View {
    var slide: Slide
    var onLink: (ElementLink) -> Void
    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / SlideSize.width
            ForEach(slide.elements.filter { $0.link != nil }) { e in
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: e.frame.w * k, height: e.frame.h * k)
                    .rotationEffect(.degrees(e.rotation))
                    .position(x: e.frame.midX * k, y: e.frame.midY * k)
                    .onTapGesture { if let l = e.link { onLink(l) } }
            }
        }
    }
}

extension Deck {
    /// Vart en länk leder från bild `from`. nil = utanför presentationen (url).
    public func target(of link: ElementLink, from: Int) -> Int? {
        switch link {
        case .nextSlide: min(from + 1, slides.count - 1)
        case .previousSlide: max(from - 1, 0)
        case .slide(let id): slideIndex(id)
        case .url: nil
        }
    }
}
