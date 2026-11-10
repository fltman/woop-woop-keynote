import SwiftUI
import SlideKit

/// Bygget live, som en sändning: "kameran" följer bilden där något händer, det som ändras
/// lyser upp i personens färg och glider på plats, och ett händelseflöde berättar vem som gör vad.
/// Fjärren: vänster/höger bläddrar (kameran pausar), upp = följ live igen,
/// klick eller play startar presentationen därifrån.
struct StageView: View {
    let session: Session
    var onLeave: () -> Void

    /// nil = följ live (bilden där något senast hände).
    @State private var pinned: Int?
    @FocusState private var focused: Bool

    private var deck: Deck { session.deck }

    private var followIndex: Int {
        if let p = pinned { return min(p, max(deck.slides.count - 1, 0)) }
        if let id = session.focusSlide ?? session.lastEditedSlide, let i = deck.slideIndex(id) { return i }
        return 0
    }

    var body: some View {
        VStack(spacing: 30) {
            header
            HStack(alignment: .top, spacing: 36) {
            if deck.slides.indices.contains(followIndex) {
                let slide = deck.slides[followIndex]
                // Tickar bara medan något lyser, annars står den still (sparar Apple TV HD:ns krafter).
                TimelineView(.animation(minimumInterval: 1 / 20, paused: !hasRecentEdits)) { ctx in
                    SlideView(slide: slide, assets: session.assets, drags: drags(on: slide), marks: marks(on: slide),
                              assetVersion: session.assetVersion, glows: glows(at: ctx.date))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 30)
                        .animation(.easeOut(duration: 0.08), value: drags(on: slide))
                        .animation(.spring(duration: 0.35), value: slide)
                        .id(slide.id)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.4), value: slide.id)
            }
            // Flödet bredvid bilden, aldrig ovanpå: det man vill se är ju det som skrivs.
            feed.frame(width: 420, alignment: .topLeading)
            }
            strip
        }
        .padding(60)
        .background(Color(white: 0.08).ignoresSafeArea())
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
        .onMoveCommand { dir in
            switch dir {
            case .left: pinned = max(followIndex - 1, 0)
            case .right: pinned = min(followIndex + 1, deck.slides.count - 1)
            case .up: pinned = nil
            default: break
            }
        }
        .onTapGesture { present() }
        .onPlayPauseCommand { present() }
        .onExitCommand { onLeave() }
    }

    // MARK: Live

    private static let glowTime = 1.6
    private var hasRecentEdits: Bool {
        session.recentEdits.values.contains { Date().timeIntervalSince($0.at) < Self.glowTime }
    }

    private func glows(at now: Date) -> [UUID: Glow] {
        var g: [UUID: Glow] = [:]
        for (e, r) in session.recentEdits {
            let age = now.timeIntervalSince(r.at)
            guard age < Self.glowTime, let p = session.peers.first(where: { $0.id == r.peer }) else { continue }
            g[e] = Glow(color: p.color, strength: 1 - age / Self.glowTime)
        }
        return g
    }

    /// De senaste händelserna; varje rad syns i åtta sekunder.
    private var feed: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let rows = session.activity.filter { ctx.date.timeIntervalSince($0.at) < 12 }.suffix(5)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(rows)) { a in
                    let color = session.peers.first { $0.id == a.peer }?.color.color ?? .gray
                    HStack(alignment: .top, spacing: 14) {
                        Circle().fill(color).frame(width: 18, height: 18).padding(.top, 8)
                        Text(a.text).font(.system(size: 28, weight: .semibold)).lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.4), value: rows.map(\.id))
        }
    }

    private func present() {
        guard session.link == .connected else { return }
        session.setPresent(PresentState(isPresenting: true, slideIndex: followIndex))
    }

    private var header: some View {
        HStack(spacing: 24) {
            Text(deck.title).font(.title2.bold()).lineLimit(1)
            Label(pinned == nil ? "LIVE" : "Bläddrar – tryck upp för live",
                  systemImage: pinned == nil ? "dot.radiowaves.left.and.right" : "pause.fill")
                .font(.headline)
                .foregroundStyle(pinned == nil ? .red : .secondary)
            Spacer()
            ForEach(session.peers.filter { $0.role == .editor }) { p in
                Label(p.name, systemImage: "person.fill")
                    .font(.headline)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(p.color.color, in: Capsule())
            }
            switch session.link {
            case .connecting: ProgressView()
            case .lost:
                // Låst telefon eller appen i bakgrunden; TV:n ansluter igen av sig själv.
                Label("Väntar på telefonen … öppna Woop Woop igen", systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
            default: EmptyView()
            }
        }
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Array(deck.slides.enumerated()), id: \.element.id) { i, s in
                        SlideView(slide: s, assets: session.assets, assetVersion: session.assetVersion)
                            .frame(width: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(i == followIndex ? .white : .clear, lineWidth: 5)
                            }
                            .overlay(alignment: .bottomTrailing) { peerDots(on: s) }
                            .id(s.id)
                    }
                }
                .padding(.vertical, 10)
            }
            .onChange(of: followIndex) { _, i in
                if deck.slides.indices.contains(i) { withAnimation { proxy.scrollTo(deck.slides[i].id, anchor: .center) } }
            }
        }
        .frame(height: 150)
    }

    private func peerDots(on s: Slide) -> some View {
        HStack(spacing: -8) {
            ForEach(session.peers.filter { p in session.presence[p.id]?.slide == s.id }) { p in
                Text(String(p.name.prefix(1))).font(.caption.bold())
                    .frame(width: 36, height: 36).background(p.color.color, in: Circle())
            }
        }
        .padding(6)
    }

    private func marks(on s: Slide) -> [UUID: Peer] {
        var m: [UUID: Peer] = [:]
        for (e, pid) in session.locks where s.element(e) != nil {
            if let p = session.peers.first(where: { $0.id == pid }) { m[e] = p }
        }
        return m
    }

    private func drags(on s: Slide) -> [UUID: DragPreview] {
        var d: [UUID: DragPreview] = [:]
        for p in session.presence.values where p.slide == s.id { if let x = p.drag { d[x.element] = x } }
        return d
    }
}

/// Presentation på TV:n. Fjärren styr för alla.
struct TVPresent: View {
    let session: Session
    @FocusState private var focused: Bool

    var body: some View {
        PresentationView(deck: session.deck, index: session.present.slideIndex,
                         assets: session.assets, assetVersion: session.assetVersion)
            .focusable()
            .focused($focused)
            .onAppear { focused = true }
            .onMoveCommand { dir in
                switch dir {
                case .left: session.remote(.previous)
                case .right: session.remote(.next)
                default: break
                }
            }
            .onTapGesture { session.remote(.next) }
            .onPlayPauseCommand { session.remote(.stop) }
            .onExitCommand { session.remote(.stop) }
    }
}
