import SwiftUI

/// Helskärmspresentation, samma på iPad och Apple TV.
/// Bildbytet animeras med målbildens övergång.
public struct PresentationView: View {
    public var deck: Deck
    public var state: PresentState
    public var assets: AssetStore
    public var assetVersion: Int
    /// Den som presenterar ser dolda element som spöken; presentationsskärmen ser dem inte alls.
    public var presenter: Bool
    /// Bara presentationsskärmen spelar ljud.
    public var playsSound: Bool
    /// Tryck på ett element som har länk, ljud eller är dolt (bara på enheter med pekskärm).
    public var onTapElement: ((Element) -> Void)?
    /// Reaktioner, laserpekare, streck, ljudknappar och röster.
    public var live: LiveState
    /// Den som presenterar kan peka eller rita på bilden med fingret.
    public var tool: LiveTool?
    public var inkColor: RGBA
    public var onLive: ((LiveEvent) -> Void)?
    @State private var bursts: [Burst] = []
    @State private var alarms: [UUID: Date] = [:]

    @State private var shown: Int
    /// Bilden vi lämnar, medan bytet pågår.
    @State private var leaving: Int?
    /// Det som var dolt på bilden vi lämnar, så att inget poppar fram mitt i bytet.
    @State private var leavingHidden: Set<UUID> = []
    @State private var progress: Double = 1
    @State private var forward = true
    @State private var kind: DeckTransition = .none

    public init(deck: Deck, state: PresentState, assets: AssetStore, assetVersion: Int = 0,
                presenter: Bool = false, playsSound: Bool = true, onTapElement: ((Element) -> Void)? = nil,
                live: LiveState = LiveState(), tool: LiveTool? = nil, inkColor: RGBA = RGBA(hex: "FF4757"),
                onLive: ((LiveEvent) -> Void)? = nil) {
        self.deck = deck; self.state = state; self.assets = assets; self.assetVersion = assetVersion
        self.presenter = presenter; self.playsSound = playsSound; self.onTapElement = onTapElement
        self.live = live; self.tool = tool; self.inkColor = inkColor; self.onLive = onLive
        _shown = State(initialValue: state.slideIndex)
    }

    private var index: Int { state.slideIndex }

    private func hidden(_ slide: Slide) -> Set<UUID> {
        // Bilden som visas har ett byggläge; bilden vi lämnar behåller det den hade.
        guard slide.id == deck.slides[safe: index]?.id else { return leavingHidden }
        return state.hidden(on: slide)
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Color.black
                // Bytet ritas uttryckligen: båda bilderna, placerade efter förloppet 0…1.
                // (SwiftUI:s in-/uttransitioner tog bort den gamla bilden direkt.)
                if let l = leaving, let slide = deck.slides[safe: l] {
                    slideView(slide, tappable: false)
                        .offset(x: outgoingOffset(w))
                        .scaleEffect(kind == .zoom ? 1 + 0.5 * progress : 1)
                        .opacity(kind == .zoom ? 1 - progress : (kind == .flip && progress > 0.5 ? 0 : 1))
                        .rotation3DEffect(.degrees(kind == .flip ? -180 * min(progress, 0.5) : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                }
                if let slide = deck.slides[safe: shown] {
                    slideView(slide, tappable: true)
                        .offset(x: incomingOffset(w))
                        .opacity(leaving == nil ? 1 : (kind == .fade || kind == .zoom ? progress : (kind == .flip && progress < 0.5 ? 0 : 1)))
                        .scaleEffect(kind == .zoom && leaving != nil ? 0.6 + 0.4 * progress : 1)
                        .rotation3DEffect(.degrees(kind == .flip && leaving != nil ? 180 * (1 - max(progress, 0.5)) : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                }
                // Det som läggs över bilden: rityta, hjul, buzzer, publikfråga, prispall och reaktioner.
                if live.board { BoardSurface(live: live) }
                if let wheel = live.wheel { WheelOverlay(spin: wheel).id(wheel.nonce) }
                if live.buzzerArmed || live.buzzWinner != nil { BuzzOverlay(armed: live.buzzerArmed, winner: live.buzzWinner) }
                if let q = live.shownQuestion { QuestionOverlay(question: q) }
                if live.showScores { ScoreboardOverlay(scores: live.scores) }
                ReactionsLayer(reactions: live.reactions)
            }
        }
        .ignoresSafeArea()
        .animation(.spring(duration: 0.4), value: [live.showScores, live.buzzerArmed, live.buzzWinner != nil, live.shownQuestion != nil, live.wheel != nil, live.board])
        .onChange(of: live.wheel?.nonce) { _, n in
            // Trumvirvel medan hjulet snurrar, fanfar när det stannar.
            guard playsSound, let n else { return }
            SoundPlayer.shared.play(.drumroll, nonce: n)
            DispatchQueue.main.asyncAfter(deadline: .now() + WheelOverlay.duration) { SoundPlayer.shared.play(.tada, nonce: UUID()) }
        }
        .onChange(of: live.buzzWinner) { _, w in if playsSound, w != nil { SoundPlayer.shared.play(.boing, nonce: UUID()) } }
        .onChange(of: live.timers) { _, timers in
            // Larm när en nedräkning når noll (om den inte har nollställts under tiden).
            alarms = timers
            guard playsSound else { return }
            for (id, end) in timers where end > Date() {
                DispatchQueue.main.asyncAfter(deadline: .now() + end.timeIntervalSinceNow) {
                    if alarms[id] == end { SoundPlayer.shared.play(.buzzer, nonce: UUID()) }
                }
            }
        }
        .onChange(of: live.jingleNonce) { _, n in
            if playsSound, let n, let j = live.jingle { SoundPlayer.shared.play(j, nonce: n) }
        }
        .onChange(of: state) { old, now in
            // Konfetti där ett element med den effekten just visades. Bara på samma bild: backar man
            // till en färdigbyggd bild har inget "just visats".
            guard old.slideIndex == now.slideIndex, old.isPresenting, let slide = deck.slides[safe: index] else { return }
            for id in now.revealed where !old.revealed.contains(id) {
                guard let e = slide.element(id), e.reveal == .confetti else { continue }
                let b = Burst(x: e.frame.midX, y: e.frame.midY)
                bursts.append(b)
                DispatchQueue.main.asyncAfter(deadline: .now() + Burst.life + 0.1) { bursts.removeAll { $0.id == b.id } }
            }
        }
        .onChange(of: state.sound) { _, cue in
            if playsSound, let cue { SoundPlayer.shared.play(cue, assets: assets) }
        }
        .onChange(of: state) { old, _ in
            guard old.slideIndex != state.slideIndex, let s = deck.slides[safe: old.slideIndex] else { return }
            leavingHidden = old.hidden(on: s)
        }
        .onChange(of: index) { old, new in
            let tr = deck.slides[safe: new]?.transition ?? .none
            guard tr != .none, deck.slides.indices.contains(old) else { shown = new; leaving = nil; return }
            forward = new >= old
            kind = tr
            leaving = old
            shown = new
            progress = 0
            withAnimation(.easeInOut(duration: 0.5)) { progress = 1 } completion: {
                if shown == new { leaving = nil }
            }
        }
    }

    private func slideView(_ slide: Slide, tappable: Bool) -> some View {
        SlideView(slide: slide, assets: assets, assetVersion: assetVersion,
                  hidden: hidden(slide), ghosts: presenter)
            .environment(\.liveState, live)
            .environment(\.showsPlaceholders, false)
            .environment(\.playsMotion, true)
            .environment(\.videoMode, playsSound ? .sound : .muted)
            .animation(.spring(duration: 0.6, bounce: 0.35), value: [state.revealed, state.gone])
            .overlay {
                if tappable, let onTapElement { TapTargets(slide: slide, hidden: hidden(slide), onTap: onTapElement) }
            }
            .overlay {
                if tappable { LiveLayer(live: live, bursts: bursts, tool: tool, inkColor: inkColor, onLive: onLive) }
            }
    }

    /// Skjut: båda flyttar. Svep: den nya glider in över den gamla. Tona: den nya tonar in över den gamla.
    private func incomingOffset(_ w: Double) -> Double {
        guard leaving != nil, kind == .push || kind == .wipe else { return 0 }
        return (1 - progress) * w * (forward ? 1 : -1)
    }

    private func outgoingOffset(_ w: Double) -> Double {
        guard kind == .push else { return 0 }
        return -progress * w * (forward ? 1 : -1)
    }
}

/// Osynliga tryckytor över element man kan trycka på: dolda, med länk eller med ljud.
/// De översta elementen ligger sist och vinner, precis som på bilden.
struct TapTargets: View {
    var slide: Slide
    var hidden: Set<UUID>
    var onTap: (Element) -> Void
    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / SlideSize.width
            ForEach(slide.elements.filter { $0.link != nil || $0.sound != nil || $0.vanishes || $0.isQuiz || $0.isTimer || hidden.contains($0.id) }) { e in
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: e.frame.w * k, height: e.frame.h * k)
                    .rotationEffect(.degrees(e.rotation))
                    .position(x: e.frame.midX * k, y: e.frame.midY * k)
                    .onTapGesture { onTap(e) }
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

extension Element {
    /// Quizfråga: tryck visar (eller gömmer) rätt svar.
    public var isQuiz: Bool { if case .poll(let p) = content { p.correct != nil } else { false } }
}

public enum LiveTool: Sendable { case laser, pen }

/// Konfettiskur när ett element med den effekten visas.
struct Burst: Identifiable, Equatable {
    static let life = 1.8
    let id = UUID()
    var x: Double, y: Double
    var start = Date()
}

/// Det som ritas ovanpå bilden under presentationen: streck, laserpekare och konfetti.
/// Med ett verktyg valt fångar lagret också fingret.
struct LiveLayer: View {
    var live: LiveState
    var bursts: [Burst]
    var tool: LiveTool?
    var inkColor: RGBA
    var onLive: ((LiveEvent) -> Void)?
    @State private var current: InkStroke?
    @State private var lastSent = Date.distantPast

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / SlideSize.width
            ZStack {
                Canvas { ctx, _ in
                    for s in live.ink where s.points.count > 0 {
                        var p = Path()
                        p.move(to: CGPoint(x: s.points[0].x * k, y: s.points[0].y * k))
                        for pt in s.points.dropFirst() { p.addLine(to: CGPoint(x: pt.x * k, y: pt.y * k)) }
                        if s.points.count == 1 { p.addLine(to: CGPoint(x: s.points[0].x * k + 0.1, y: s.points[0].y * k)) }
                        ctx.stroke(p, with: .color(s.color.color), style: StrokeStyle(lineWidth: s.width * k, lineCap: .round, lineJoin: .round))
                    }
                }
                if !bursts.isEmpty {
                    TimelineView(.animation) { tl in
                        Canvas { ctx, _ in
                            for b in bursts { Self.draw(b, at: tl.date, k: k, in: &ctx) }
                        }
                    }
                }
                if let p = live.pointer {
                    Circle().fill(Color.red)
                        .frame(width: 26 * k, height: 26 * k)
                        .shadow(color: .red, radius: 14 * k)
                        .shadow(color: .red.opacity(0.8), radius: 30 * k)
                        .position(x: p.x * k, y: p.y * k)
                        .animation(.linear(duration: 0.05), value: p)
                }
                #if !os(tvOS)
                if let tool, let onLive {
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 2)
                            .onChanged { v in
                                let spot = Spot(x: v.location.x / k, y: v.location.y / k)
                                switch tool {
                                case .laser:
                                    guard Date().timeIntervalSince(lastSent) > 1 / 30 else { return }
                                    lastSent = Date()
                                    onLive(.pointer(spot))
                                case .pen:
                                    var s = current ?? InkStroke(points: [], color: inkColor)
                                    if let l = s.points.last, hypot(l.x - spot.x, l.y - spot.y) < 4 { return }
                                    guard s.points.count < 600 else { return }
                                    s.points.append(spot)
                                    current = s
                                    guard Date().timeIntervalSince(lastSent) > 1 / 20 else { return }
                                    lastSent = Date()
                                    onLive(.stroke(s))
                                }
                            }
                            .onEnded { _ in
                                switch tool {
                                case .laser: onLive(.pointer(nil))
                                case .pen: if let s = current { onLive(.stroke(s)) }; current = nil
                                }
                            })
                }
                #endif
            }
        }
        .allowsHitTesting(tool != nil && onLive != nil)
    }

    static let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .white]

    static func draw(_ b: Burst, at now: Date, k: Double, in ctx: inout GraphicsContext) {
        let t = now.timeIntervalSince(b.start)
        guard t >= 0, t < Burst.life else { return }
        var rng = SplitMix(seed: UInt64(truncatingIfNeeded: b.id.hashValue))
        func rnd() -> Double { Double(rng.next() >> 11) / Double(1 << 53) }
        for i in 0..<90 {
            let angle = rnd() * 2 * .pi, speed = 500 + rnd() * 1300
            let size = (14 + rnd() * 18) * k, spin = rnd() * 12 - 6
            // Luftmotstånd: farten avtar; sedan faller bitarna.
            let d = (1 - exp(-t * 2.2)) / 2.2
            let x = (b.x + cos(angle) * speed * d) * k
            let y = (b.y + sin(angle) * speed * d - 250 * d + 900 * t * t) * k
            var c = ctx
            c.opacity = min(1, (Burst.life - t) / 0.5)
            c.translateBy(x: x, y: y)
            c.rotate(by: .radians(spin * t))
            c.fill(Path(CGRect(x: -size / 2, y: -size / 4, width: size, height: size / 2)), with: .color(colors[i % colors.count]))
        }
    }
}

/// Publikens reaktioner flyger upp över bilden.
struct ReactionsLayer: View {
    var reactions: [Reaction]
    var body: some View {
        if !reactions.isEmpty {
            GeometryReader { geo in
                TimelineView(.animation) { tl in
                    ZStack {
                        ForEach(reactions) { r in
                            let t = tl.date.timeIntervalSince(r.at), u = t / LiveState.reactionTime
                            if u >= 0, u < 1 {
                                Text(r.emoji)
                                    .font(.system(size: geo.size.height * 0.1))
                                    .scaleEffect(min(t / 0.25, 1))
                                    .opacity(u < 0.7 ? 1 : (1 - u) / 0.3)
                                    .position(x: (r.lane + sin(t * 3 + r.lane * 20) * 0.02) * geo.size.width,
                                              y: geo.size.height * (1.02 - u * 0.9))
                            }
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
