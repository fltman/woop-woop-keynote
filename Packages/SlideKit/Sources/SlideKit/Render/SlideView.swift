import SwiftUI

extension RGBA {
    public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

extension Fill {
    /// Start/slut för en linjär gradient. 0° = vänster→höger, 90° = uppifrån och ned (som i .pptx).
    static func points(angle: Double) -> (UnitPoint, UnitPoint) {
        let t = angle * .pi / 180
        let dx = cos(t) / 2, dy = sin(t) / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

/// Ett element som just ändrats lyser upp i personens färg och tonar bort.
public struct Glow: Equatable, Sendable {
    public var color: RGBA
    public var strength: Double
    public init(color: RGBA, strength: Double) { self.color = color; self.strength = strength }
}

/// Ritar en bild i bildenheter (1920×1080) och skalar till tillgänglig yta.
/// Samma vy används i editorn, på scenen, i presentationen och för PDF-export.
public struct SlideView: View {
    public var slide: Slide
    public var assets: AssetStore
    /// Element som någon drar i just nu (live på scenen).
    public var drags: [UUID: DragPreview]
    /// Element som någon har markerat, med deras färg och namn.
    public var marks: [UUID: Peer]
    /// Ritar om när nya bilder kommit från nätet.
    public var assetVersion: Int
    public var glows: [UUID: Glow]
    /// Dolda "visa när jag trycker"-element. Utan `ghosts` syns de inte alls (presentationsskärmen);
    /// med `ghosts` syns de svagt med streckad ram (den som presenterar ska se var de finns).
    public var hidden: Set<UUID>
    public var ghosts: Bool

    public init(slide: Slide, assets: AssetStore, drags: [UUID: DragPreview] = [:],
                marks: [UUID: Peer] = [:], assetVersion: Int = 0, glows: [UUID: Glow] = [:],
                hidden: Set<UUID> = [], ghosts: Bool = false) {
        self.slide = slide; self.assets = assets; self.drags = drags
        self.marks = marks; self.assetVersion = assetVersion; self.glows = glows
        self.hidden = hidden; self.ghosts = ghosts
    }

    public var body: some View {
        GeometryReader { geo in
            SlideCanvas(slide: slide, assets: assets, drags: drags, marks: marks, assetVersion: assetVersion,
                        glows: glows, hidden: hidden, ghosts: ghosts)
                .scaleEffect(geo.size.width / SlideSize.width, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .aspectRatio(SlideSize.width / SlideSize.height, contentMode: .fit)
        .clipped()
    }
}

/// Bilden i full storlek, 1920×1080 punkter, utan skalning.
public struct SlideCanvas: View {
    public var slide: Slide
    public var assets: AssetStore
    public var drags: [UUID: DragPreview] = [:]
    public var marks: [UUID: Peer] = [:]
    public var assetVersion: Int = 0
    public var glows: [UUID: Glow] = [:]
    public var hidden: Set<UUID> = []
    public var ghosts = false
    @Environment(\.playsMotion) private var playsMotion

    public init(slide: Slide, assets: AssetStore, drags: [UUID: DragPreview] = [:],
                marks: [UUID: Peer] = [:], assetVersion: Int = 0, glows: [UUID: Glow] = [:],
                hidden: Set<UUID> = [], ghosts: Bool = false) {
        self.slide = slide; self.assets = assets; self.drags = drags
        self.marks = marks; self.assetVersion = assetVersion; self.glows = glows
        self.hidden = hidden; self.ghosts = ghosts
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            FillView(fill: slide.background, assets: assets)
            ForEach(slide.elements) { e in
                let d = drags[e.id]
                let f = d?.frame ?? e.frame
                let isHidden = hidden.contains(e.id)
                // Behållaren har elementets storlek, så att effekten (t.ex. "poppa upp") utgår från elementets mitt.
                ZStack {
                    if !isHidden || ghosts {
                        ElementView(element: e, assets: assets)
                            .modifier(MotionModifier(motion: playsMotion ? e.motion : nil, seed: Double(abs(e.id.hashValue % 1000)) / 100))
                            .opacity(isHidden ? 0.3 : 1)
                            .overlay { if isHidden { GhostMark() } }
                            .transition(e.reveal?.transition ?? (e.vanishes ? AppearEffect.pop.transition : .identity))
                    }
                }
                    .frame(width: max(f.w, 1), height: max(f.h, 1))
                    .overlay {
                        if let g = glows[e.id], g.strength > 0 {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(g.color.color.opacity(g.strength), lineWidth: 10)
                                .shadow(color: g.color.color.opacity(g.strength), radius: 24)
                                .padding(-14)
                        }
                    }
                    .overlay { if let p = marks[e.id] { MarkView(peer: p) } }
                    .rotationEffect(.degrees(d?.rotation ?? e.rotation))
                    .position(x: f.midX, y: f.midY)
            }
        }
        .frame(width: SlideSize.width, height: SlideSize.height, alignment: .topLeading)
        .clipped()
        .id(assetVersion)
    }
}

/// Så ser ett dolt element ut för den som presenterar: tryck här så visas det.
struct GhostMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(style: StrokeStyle(lineWidth: 6, dash: [18, 12]))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.6), radius: 4)
            .overlay {
                Image(systemName: "hand.tap.fill").font(.system(size: 64)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6)
            }
    }
}

extension AppearEffect {
    /// Effekten i bildenheter (bildytan är 1920×1080, så 2200 är helt utanför).
    public var transition: AnyTransition {
        switch self {
        case .fade: .opacity
        case .pop: .scale(scale: 0.05).combined(with: .opacity)
        case .flyUp: .offset(y: 1300)
        case .flyFromLeft: .offset(x: -2300)
        case .flyFromRight: .offset(x: 2300)
        case .spin: .modifier(active: Spin(turns: -1.5, scale: 0.05), identity: Spin(turns: 0, scale: 1)).combined(with: .opacity)
        // Studsen kommer från fjädern som presentationen animerar med.
        case .bounce: .offset(y: -1300)
        case .confetti: .scale(scale: 0.05).combined(with: .opacity)
        }
    }
}

struct Spin: ViewModifier {
    var turns: Double
    var scale: Double
    func body(content: Spin.Content) -> some View {
        content.rotationEffect(.degrees(turns * 360)).scaleEffect(scale)
    }
}

struct MarkView: View {
    var peer: Peer
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(peer.color.color, lineWidth: 6)
            .padding(-10)
            .overlay(alignment: .topLeading) {
                Text(peer.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(peer.color.color, in: Capsule())
                    .fixedSize()
                    .offset(x: -10, y: -58)
            }
    }
}

public struct FillView: View {
    public var fill: Fill
    public var assets: AssetStore
    public init(fill: Fill, assets: AssetStore) { self.fill = fill; self.assets = assets }
    public var body: some View {
        switch fill {
        case .solid(let c):
            Rectangle().fill(c.color)
        case .gradient(let a, let b, let angle):
            let (s, e) = Fill.points(angle: angle)
            Rectangle().fill(LinearGradient(colors: [a.color, b.color], startPoint: s, endPoint: e))
        case .image(let id):
            if let cg = assets.cgImage(id) {
                Image(decorative: cg, scale: 1).resizable()
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
        }
    }
}

public struct ElementView: View {
    public var element: Element
    public var assets: AssetStore
    @Environment(\.showsPlaceholders) private var showsPlaceholders
    public init(element: Element, assets: AssetStore) { self.element = element; self.assets = assets }

    public var body: some View {
        if element.isSticky {
            // En lapp till dem som bygger: syns aldrig i presentationen.
            if showsPlaceholders { StickyView(element: element) }
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch element.content {
        case .text(let t):
            TextBoxView(box: t, width: element.frame.w, height: element.frame.h)
        case .shape(let s):
            ShapeView(box: s)
        case .image(let i):
            if i.isPlaceholder {
                if showsPlaceholders { ImagePlaceholderView(width: element.frame.w, height: element.frame.h) }
            } else if i.isVideo {
                VideoElementView(assetID: i.assetID, assets: assets)
            } else if let anim = assets.animation(i.assetID) {
                AnimatedImage(animation: anim)
            } else if let cg = assets.cgImage(i.assetID) {
                Image(decorative: cg, scale: 1).resizable()
            } else {
                Rectangle().fill(Color.gray.opacity(0.25))
                    .overlay { Image(systemName: "photo").font(.system(size: 80)).foregroundStyle(.secondary) }
            }
        case .poll(let p):
            PollView(id: element.id, box: p, width: element.frame.w, height: element.frame.h)
        case .timer(let t):
            TimerView(id: element.id, box: t, width: element.frame.w, height: element.frame.h)
        case .chart(let c):
            ChartView(box: c, width: element.frame.w, height: element.frame.h)
        }
    }
}

/// En bildplats: tryck för att välja en bild. Syns på alla bakgrunder (ljus kant, mörk skugga).
struct ImagePlaceholderView: View {
    var width: Double
    var height: Double
    var body: some View {
        let u = min(width, height)
        ZStack {
            RoundedRectangle(cornerRadius: u * 0.06).fill(Color.gray.opacity(0.35))
            RoundedRectangle(cornerRadius: u * 0.06)
                .stroke(style: StrokeStyle(lineWidth: max(u * 0.012, 4), dash: [u * 0.05, u * 0.035]))
                .foregroundStyle(.white.opacity(0.9))
            VStack(spacing: u * 0.04) {
                Image(systemName: "photo.badge.plus").font(.system(size: u * 0.22, weight: .semibold))
                if u > 220 { Text("Tryck för att lägga till en bild").font(.custom("Arial", fixedSize: max(u * 0.07, 28))).bold() }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(u * 0.06)
        }
        .shadow(color: .black.opacity(0.35), radius: 6)
    }
}

extension EnvironmentValues {
    /// Bildplatser syns när man bygger, men aldrig i presentationen eller i PDF-exporten.
    @Entry public var showsPlaceholders = true
    /// Av i miniatyrer: en remsa full av GIF:ar som rör sig är både rörig och dyr.
    @Entry public var animatesImages = true
}

/// Spelar en animerad GIF. Står still på första rutan när animationer är avstängda.
public struct AnimatedImage: View {
    public var animation: GIFAnimation
    @Environment(\.animatesImages) private var animates
    public init(animation: GIFAnimation) { self.animation = animation }
    public var body: some View {
        if animates {
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                Image(decorative: animation.frame(at: ctx.date), scale: 1).resizable()
            }
        } else {
            Image(decorative: animation.frames[0], scale: 1).resizable()
        }
    }
}

struct TextBoxView: View {
    var box: TextBox
    var width: Double
    var height: Double

    var body: some View {
        let s = box.style
        let h: HorizontalAlignment = switch s.align { case .leading: .leading; case .center: .center; case .trailing: .trailing }
        let ta: TextAlignment = switch s.align { case .leading: .leading; case .center: .center; case .trailing: .trailing }
        // Text som inte får plats rinner ut nedåt i stället för att kapas, precis som i .pptx.
        Text(box.text.isEmpty ? " " : box.text)
            .font(.custom(s.font.rawValue, fixedSize: s.size))
            .bold(s.bold)
            .italic(s.italic)
            .foregroundStyle(s.color.color)
            .multilineTextAlignment(ta)
            .frame(width: width, alignment: Alignment(horizontal: h, vertical: .top))
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, height: height, alignment: .top)
    }
}

struct ShapeView: View {
    var box: ShapeBox
    var body: some View {
        let shape = AnyShape(Self.shape(box.kind))
        shape.fill(box.fill.color)
            .overlay {
                if let st = box.stroke, box.strokeWidth > 0 { shape.stroke(st.color, lineWidth: box.strokeWidth) }
            }
    }

    static func shape(_ kind: ShapeKind) -> any Shape {
        switch kind {
        case .rectangle: Rectangle()
        case .roundedRectangle: PresetRoundRect()
        case .ellipse: Ellipse()
        case .triangle: Triangle()
        case .star: Star()
        case .arrow: RightArrow()
        case .heart: Heart()
        }
    }
}

// Formerna följer .pptx-presetens standardgeometri så att exporten ser likadan ut.

struct PresetRoundRect: Shape {
    func path(in r: CGRect) -> Path {
        Path(roundedRect: r, cornerRadius: min(r.width, r.height) * 0.16667, style: .circular)
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// star5: spetsarna på en ellips som fyller rutan, inre radie 19098/50000 av den yttre
/// (presetens adj), förskjuten nedåt som i PowerPoint.
struct Star: Shape {
    func path(in r: CGRect) -> Path {
        let hf = 1.05146, vf = 1.10557
        let rx = r.width / 2 * hf, ry = r.height / 2 * vf
        let cx = r.midX, cy = r.minY + ry
        let inner = 0.19098 / 0.5
        var p = Path()
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double(i) * .pi / 5
            let k = i.isMultiple(of: 2) ? 1.0 : inner
            let pt = CGPoint(x: cx + cos(a) * rx * k, y: cy + sin(a) * ry * k)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

/// rightArrow med standardvärden: skaftet är 50 % av höjden, spetsen är 50 % av min(b, h) lång.
struct RightArrow: Shape {
    func path(in r: CGRect) -> Path {
        let head = min(r.width, r.height) * 0.5
        let shaft = r.height * 0.25
        let x = r.maxX - head
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY - shaft))
        p.addLine(to: CGPoint(x: x, y: r.midY - shaft))
        p.addLine(to: CGPoint(x: x, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: x, y: r.maxY))
        p.addLine(to: CGPoint(x: x, y: r.midY + shaft))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY + shaft))
        p.closeSubpath()
        return p
    }
}

/// heart-preseten i OOXML (presetShapeDefinitions): från (hc, h/4) två kubiska kurvor
/// med kontrollpunkter på hc ± w·10/48 (ovanför rutan, −h/3) och hc ± w·49/48 (h/4).
struct Heart: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, hc = r.midX, t = r.minY
        let top = CGPoint(x: hc, y: t + h / 4)
        var p = Path()
        p.move(to: top)
        p.addCurve(to: CGPoint(x: hc, y: r.maxY),
                   control1: CGPoint(x: hc + w * 10 / 48, y: t - h / 3),
                   control2: CGPoint(x: hc + w * 49 / 48, y: t + h / 4))
        p.addCurve(to: top,
                   control1: CGPoint(x: hc - w * 49 / 48, y: t + h / 4),
                   control2: CGPoint(x: hc - w * 10 / 48, y: t - h / 3))
        p.closeSubpath()
        return p
    }
}
