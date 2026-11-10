import SwiftUI
import AVFoundation

// Det som kom till efter grunden: nedräkning, diagram, lappar, video, rörelse,
// och det som läggs över presentationen (prispall, buzzer, hjul, publikfrågor, rityta).

extension EnvironmentValues {
    /// Hur videoklipp visas: stillbild när man bygger, spelas i presentationen.
    @Entry public var videoMode = VideoMode.poster
    /// Rörelse (gunga, pulsera …) spelas bara i presentationen.
    @Entry public var playsMotion = false
}

public enum VideoMode: Sendable { case poster, muted, sound }

// MARK: - Nedräkning

struct TimerView: View {
    var id: UUID
    var box: TimerBox
    var width: Double
    var height: Double
    @Environment(\.liveState) private var live

    var body: some View {
        let u = min(width, height)
        if let end = live.timers[id] {
            TimelineView(.periodic(from: .now, by: 0.1)) { tl in
                let left = end.timeIntervalSince(tl.date)
                face(seconds: Int(left.rounded(.up)), fraction: left / Double(max(box.seconds, 1)),
                     alarm: left <= 0 && Int(tl.date.timeIntervalSinceReferenceDate * 3) % 2 == 0, u: u)
            }
        } else {
            face(seconds: box.seconds, fraction: 1, alarm: false, u: u)
        }
    }

    private func face(seconds: Int, fraction: Double, alarm: Bool, u: Double) -> some View {
        ZStack {
            Circle().stroke(box.color.color.opacity(0.22), lineWidth: u * 0.08)
            Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(alarm ? Color.red : box.color.color, style: StrokeStyle(lineWidth: u * 0.08, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(TimerBox.label(seconds))
                .font(.custom("Arial", fixedSize: u * 0.26)).bold().monospacedDigit()
                .foregroundStyle(alarm ? Color.red : box.color.color)
        }
        .padding(u * 0.06)
        .frame(width: width, height: height)
    }
}

// MARK: - Diagram

struct ChartView: View {
    var box: ChartBox
    var width: Double
    var height: Double

    static func palette(_ accent: RGBA) -> [Color] {
        [accent.color] + ["1E90FF", "2ED573", "FFA502", "A55EEA", "FF6B81", "00D2D3", "FF4757"].map { RGBA(hex: $0).color }
    }

    var body: some View {
        let pad = min(width, height) * 0.05
        let tSize = min(height * 0.1, 72)
        let colors = Self.palette(box.accent)
        let rows = Array(zip(box.labels, box.values).enumerated())
        VStack(alignment: .leading, spacing: pad * 0.6) {
            if !box.title.isEmpty {
                Text(box.title).font(.custom("Arial", fixedSize: tSize)).bold().lineLimit(1).minimumScaleFactor(0.5)
            }
            switch box.kind {
            case .bar:
                let top = max(box.values.max() ?? 1, 0.0001)
                HStack(alignment: .bottom, spacing: pad * 0.6) {
                    ForEach(rows, id: \.offset) { i, row in
                        VStack(spacing: pad * 0.25) {
                            Text(row.1.formatted()).font(.custom("Arial", fixedSize: tSize * 0.55)).bold()
                            GeometryReader { g in
                                VStack { Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: pad * 0.3).fill(colors[i % colors.count])
                                        .frame(height: max(g.size.height * max(row.1, 0) / top, 4))
                                }
                            }
                            Text(row.0).font(.custom("Arial", fixedSize: tSize * 0.5)).lineLimit(1).minimumScaleFactor(0.4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            case .pie:
                let total = max(box.values.map { max($0, 0) }.reduce(0, +), 0.0001)
                HStack(spacing: pad) {
                    Canvas { ctx, size in
                        let r = min(size.width, size.height) / 2, c = CGPoint(x: size.width / 2, y: size.height / 2)
                        var a = -Double.pi / 2
                        for (i, row) in rows {
                            let sweep = max(row.1, 0) / total * 2 * .pi
                            var p = Path()
                            p.move(to: c)
                            p.addArc(center: c, radius: r, startAngle: .radians(a), endAngle: .radians(a + sweep), clockwise: false)
                            p.closeSubpath()
                            ctx.fill(p, with: .color(colors[i % colors.count]))
                            a += sweep
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    VStack(alignment: .leading, spacing: pad * 0.3) {
                        ForEach(rows, id: \.offset) { i, row in
                            HStack(spacing: pad * 0.3) {
                                RoundedRectangle(cornerRadius: 4).fill(colors[i % colors.count]).frame(width: tSize * 0.5, height: tSize * 0.5)
                                Text("\(row.0)  \(Int((max(row.1, 0) / total * 100).rounded())) %")
                                    .font(.custom("Arial", fixedSize: tSize * 0.5)).lineLimit(1).minimumScaleFactor(0.4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(box.textColor.color)
        .padding(pad)
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

// MARK: - Lapp (kommentar till dem som bygger)

struct StickyView: View {
    var element: Element
    var body: some View {
        let text: String = { if case .text(let t) = element.content { t.text } else { "" } }()
        let u = min(element.frame.w, element.frame.h)
        VStack(alignment: .leading, spacing: u * 0.04) {
            Text(text.isEmpty ? " " : text).font(.custom("Arial", fixedSize: max(u * 0.14, 30)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let a = element.author, !a.isEmpty {
                Text("– \(a)").font(.custom("Arial", fixedSize: max(u * 0.1, 24))).bold().opacity(0.6)
            }
        }
        .foregroundStyle(Color(red: 0.25, green: 0.2, blue: 0))
        .padding(u * 0.08)
        .frame(width: element.frame.w, height: element.frame.h)
        .background(Color(red: 1, green: 0.92, blue: 0.45))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}

// MARK: - Video

/// Ett klipp: stillbild med spelsymbol när man bygger, spelas i slinga i presentationen.
struct VideoElementView: View {
    var assetID: String
    var assets: AssetStore
    @Environment(\.videoMode) private var mode

    var body: some View {
        if mode != .poster, assets.has(assetID) {
            LoopingVideo(url: assets.url(assetID), muted: mode == .muted)
        } else if let cg = assets.cgImage(assetID) {
            Image(decorative: cg, scale: 1).resizable()
                .overlay {
                    Image(systemName: "play.circle.fill").font(.system(size: 110))
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 8)
                }
        } else {
            Rectangle().fill(Color.gray.opacity(0.25))
                .overlay { Image(systemName: "film").font(.system(size: 80)).foregroundStyle(.secondary) }
        }
    }
}

#if os(macOS)
struct LoopingVideo: NSViewRepresentable {
    var url: URL
    var muted: Bool
    func makeNSView(context: Context) -> NSView { NSView() }   // macOS används bara för tester
    func updateNSView(_ v: NSView, context: Context) {}
}
#else
struct LoopingVideo: UIViewRepresentable {
    var url: URL
    var muted: Bool

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        let p = AVQueuePlayer()
        v.looper = AVPlayerLooper(player: p, templateItem: AVPlayerItem(url: url))
        v.player = p
        p.isMuted = muted
        (v.layer as? AVPlayerLayer)?.player = p
        (v.layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill
        p.play()
        return v
    }

    func updateUIView(_ v: PlayerView, context: Context) { v.player?.isMuted = muted }
    static func dismantleUIView(_ v: PlayerView, coordinator: ()) { v.player?.pause(); v.looper = nil; v.player = nil }
}
#endif

// MARK: - Rörelse

struct MotionModifier: ViewModifier {
    var motion: Motion?
    var seed: Double
    func body(content: MotionModifier.Content) -> some View {
        if let motion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate + seed
                switch motion {
                case .wobble: content.rotationEffect(.degrees(6 * sin(t * 2.4)))
                case .pulse: content.scaleEffect(1 + 0.06 * sin(t * 3.2))
                case .float: content.offset(y: 18 * sin(t * 1.6))
                case .spin: content.rotationEffect(.degrees((t * 60).truncatingRemainder(dividingBy: 360)))
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Streck

/// Ritar streck i bildenheter, skalade med `k`. Delas av presentationen, ritytan och editorn.
public struct InkCanvas: View {
    public var strokes: [InkStroke]
    public var k: Double
    public init(strokes: [InkStroke], k: Double) { self.strokes = strokes; self.k = k }
    public var body: some View {
        Canvas { ctx, _ in
            for s in strokes where !s.points.isEmpty {
                var p = Path()
                p.move(to: CGPoint(x: s.points[0].x * k, y: s.points[0].y * k))
                for pt in s.points.dropFirst() { p.addLine(to: CGPoint(x: pt.x * k, y: pt.y * k)) }
                if s.points.count == 1 { p.addLine(to: CGPoint(x: s.points[0].x * k + 0.1, y: s.points[0].y * k)) }
                ctx.stroke(p, with: .color(s.color.color), style: StrokeStyle(lineWidth: s.width * k, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Den gemensamma ritytan i helskärm: en vit tavla där allas streck syns.
public struct BoardSurface: View {
    public var live: LiveState
    public init(live: LiveState) { self.live = live }
    public var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.05, blue: 0.22).ignoresSafeArea()
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(.white)
                    InkCanvas(strokes: live.ink, k: geo.size.width / SlideSize.width)
                    if live.ink.isEmpty {
                        Text("Rita tillsammans!").font(.system(size: geo.size.height * 0.08, weight: .heavy, design: .rounded))
                            .foregroundStyle(.gray.opacity(0.4))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .aspectRatio(SlideSize.width / SlideSize.height, contentMode: .fit)
            .padding(40)
        }
    }
}

// MARK: - Det som läggs över presentationen

struct ScoreboardOverlay: View {
    var scores: [ScoreEntry]
    private static let medals = ["🥇", "🥈", "🥉"]
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            VStack(spacing: h * 0.02) {
                Text("Poängställning").font(.system(size: h * 0.08, weight: .heavy, design: .rounded))
                if scores.isEmpty {
                    Text("Inga poäng än").font(.system(size: h * 0.045)).opacity(0.7)
                }
                ForEach(Array(scores.prefix(6).enumerated()), id: \.element.id) { i, s in
                    HStack {
                        Text(i < 3 ? Self.medals[i] : "\(i + 1).").frame(width: h * 0.1)
                        Text(s.name).lineLimit(1)
                        Spacer()
                        Text("\(s.points)").monospacedDigit()
                    }
                    .font(.system(size: h * (i == 0 ? 0.065 : 0.05), weight: .bold, design: .rounded))
                    .padding(.horizontal, h * 0.04).padding(.vertical, h * 0.012)
                    .background(Color.white.opacity(i == 0 ? 0.25 : 0.12), in: RoundedRectangle(cornerRadius: h * 0.025))
                }
            }
            .foregroundStyle(.white)
            .padding(h * 0.05)
            .frame(width: min(geo.size.width * 0.7, h * 1.3))
            .background(Color(red: 0.11, green: 0.08, blue: 0.39).opacity(0.94), in: RoundedRectangle(cornerRadius: h * 0.05))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

struct BuzzOverlay: View {
    var armed: Bool
    var winner: String?
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            VStack(spacing: h * 0.02) {
                Text(winner == nil ? "🔔" : "🙋").font(.system(size: h * 0.16))
                Text(winner.map { "\($0) var först!" } ?? "Tryck på BUZZ i mobilen!")
                    .font(.system(size: h * (winner == nil ? 0.06 : 0.1), weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(h * 0.06)
            .background((winner == nil ? Color(red: 0.11, green: 0.08, blue: 0.39) : Color.red).opacity(0.94), in: RoundedRectangle(cornerRadius: h * 0.05))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

struct QuestionOverlay: View {
    var question: AudienceQuestion
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            VStack(alignment: .leading, spacing: h * 0.02) {
                Text("Fråga från \(question.name)").font(.system(size: h * 0.045, weight: .bold)).opacity(0.75)
                Text(question.text).font(.system(size: h * 0.075, weight: .heavy, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color(red: 0.11, green: 0.08, blue: 0.39))
            .padding(h * 0.06)
            .frame(maxWidth: geo.size.width * 0.8, alignment: .leading)
            .background(Color(red: 1, green: 0.76, blue: 0.07), in: RoundedRectangle(cornerRadius: h * 0.05))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Slumphjulet: snurrar i drygt tre sekunder och stannar med vinnaren överst.
struct WheelOverlay: View {
    var spin: WheelSpin
    static let duration = 3.6

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.72
            let n = spin.options.count
            let step = 360.0 / Double(max(n, 1))
            // Vinnarens mitt ska hamna rakt upp efter fem hela varv.
            let target = 360.0 * 5 - (Double(spin.winner) + 0.5) * step
            TimelineView(.animation) { tl in
                let u = min(max(tl.date.timeIntervalSince(spin.at) / Self.duration, 0), 1)
                let eased = 1 - pow(1 - u, 3)
                VStack(spacing: side * 0.04) {
                    ZStack(alignment: .top) {
                        Canvas { ctx, size in
                            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = size.width / 2
                            let colors = ChartView.palette(RGBA(hex: "FFC312"))
                            for i in 0..<n {
                                let a0 = Angle.degrees(-90 + Double(i) * step), a1 = Angle.degrees(-90 + Double(i + 1) * step)
                                var p = Path()
                                p.move(to: c); p.addArc(center: c, radius: r, startAngle: a0, endAngle: a1, clockwise: false); p.closeSubpath()
                                ctx.fill(p, with: .color(colors[i % colors.count]))
                                var t = ctx
                                let mid = (a0.radians + a1.radians) / 2
                                t.translateBy(x: c.x + cos(mid) * r * 0.6, y: c.y + sin(mid) * r * 0.6)
                                t.rotate(by: .radians(mid))
                                t.draw(Text(spin.options[i]).font(.system(size: r * 0.11, weight: .bold)).foregroundColor(.white), at: .zero)
                            }
                        }
                        .frame(width: side, height: side)
                        .rotationEffect(.degrees(target * eased))
                        .shadow(color: .black.opacity(0.5), radius: 30)
                        Image(systemName: "arrowtriangle.down.fill").font(.system(size: side * 0.08)).foregroundStyle(.white)
                            .shadow(radius: 4).offset(y: -side * 0.03)
                    }
                    Text(u >= 1 ? "🎉 \(spin.options[spin.winner])!" : " ")
                        .font(.system(size: side * 0.1, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .shadow(color: .black, radius: 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.opacity(0.6))
        .transition(.opacity)
    }
}

// MARK: - Export

extension Deck {
    /// Decket som det ska exporteras: diagram och nedräkningar blir bilder av sig själva, videoklipp
    /// blir sin stillbild, och lappar och tomma bildplatser tas bort (CONTRACT §2).
    @MainActor
    public func flattened(assets: AssetStore) -> Deck {
        var d = self
        for i in d.slides.indices {
            d.slides[i].elements.removeAll { $0.isSticky || $0.isImagePlaceholder }
            for j in d.slides[i].elements.indices {
                let e = d.slides[i].elements[j]
                var png: Data?
                switch e.content {
                case .timer, .chart:
                    let r = ImageRenderer(content: ElementView(element: e, assets: assets).frame(width: e.frame.w, height: e.frame.h))
                    r.scale = 1; r.isOpaque = false
                    png = r.cgImage.flatMap(Self.png)
                case .image(let box) where box.isVideo:
                    png = assets.cgImage(box.assetID).flatMap(Self.png)
                default: break
                }
                if let png, let id = try? assets.put(png, id: AssetStore.id(for: png, ext: "png")) {
                    d.slides[i].elements[j].content = .image(ImageBox(assetID: id))
                }
            }
        }
        return d
    }

    private static func png(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, image, nil)
        return CGImageDestinationFinalize(dst) ? out as Data : nil
    }
}
