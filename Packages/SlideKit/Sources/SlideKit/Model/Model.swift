import Foundation

// All geometri i bildenheter: bildytan är 1920×1080 (CONTRACT §1).
public enum SlideSize {
    public static let width: Double = 1920
    public static let height: Double = 1080
}

public struct RGBA: Codable, Hashable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    /// "#RRGGBB" eller "RRGGBB".
    public init(hex: String, alpha: Double = 1) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(s, radix: 16) ?? 0
        self.init(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255, alpha)
    }
    /// "RRGGBB", som .pptx vill ha det.
    public var hex: String {
        func c(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", c(r), c(g), c(b))
    }
    public static let white = RGBA(1, 1, 1)
    public static let black = RGBA(0, 0, 0)
}

public struct Frame: Codable, Hashable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
    public var midX: Double { x + w / 2 }
    public var midY: Double { y + h / 2 }
}

public enum Fill: Codable, Hashable, Sendable {
    case solid(RGBA)
    /// Vinkel i grader, 0 = vänster till höger, 90 = uppifrån och ned.
    case gradient(from: RGBA, to: RGBA, angle: Double)
    case image(assetID: String)
}

public enum FontFamily: String, Codable, CaseIterable, Sendable {
    case arial = "Arial", georgia = "Georgia", verdana = "Verdana"
    case trebuchet = "Trebuchet MS", courier = "Courier New", times = "Times New Roman"
}

public enum TextAlign: String, Codable, CaseIterable, Sendable { case leading, center, trailing }

public struct TextStyle: Codable, Hashable, Sendable {
    public var font: FontFamily
    /// I bildenheter (pt i .pptx = size × 0,5).
    public var size: Double
    public var color: RGBA
    public var bold: Bool
    public var italic: Bool
    public var align: TextAlign
    public init(font: FontFamily = .arial, size: Double = 64, color: RGBA = .black,
                bold: Bool = false, italic: Bool = false, align: TextAlign = .leading) {
        self.font = font; self.size = size; self.color = color
        self.bold = bold; self.italic = italic; self.align = align
    }
}

public struct TextBox: Codable, Hashable, Sendable {
    public var text: String
    public var style: TextStyle
    public init(text: String, style: TextStyle = TextStyle()) { self.text = text; self.style = style }
}

/// Varje form har ett preset i .pptx (prstGeom).
public enum ShapeKind: String, Codable, CaseIterable, Sendable {
    case rectangle, roundedRectangle, ellipse, triangle, star, arrow, heart
    public var pptxPreset: String {
        switch self {
        case .rectangle: "rect"
        case .roundedRectangle: "roundRect"
        case .ellipse: "ellipse"
        case .triangle: "triangle"
        case .star: "star5"
        case .arrow: "rightArrow"
        case .heart: "heart"
        }
    }
}

public struct ShapeBox: Codable, Hashable, Sendable {
    public var kind: ShapeKind
    public var fill: RGBA
    public var stroke: RGBA?
    public var strokeWidth: Double
    public init(kind: ShapeKind, fill: RGBA, stroke: RGBA? = nil, strokeWidth: Double = 0) {
        self.kind = kind; self.fill = fill; self.stroke = stroke; self.strokeWidth = strokeWidth
    }
}

public struct ImageBox: Codable, Hashable, Sendable {
    public var assetID: String
    public init(assetID: String) { self.assetID = assetID }
}

/// Omröstning eller quiz (`correct` satt). Publiken röstar med mobilen via QR-koden (CONTRACT §16).
/// Rösterna är live och sparas inte i decket. Exporteras som en textruta med frågan och alternativen.
public struct PollBox: Codable, Hashable, Sendable {
    public var question: String
    public var options: [String]
    /// Rätt svar (quiz), nil = vanlig omröstning.
    public var correct: Int?
    public var accent: RGBA
    public var textColor: RGBA
    public init(question: String, options: [String], correct: Int? = nil, accent: RGBA, textColor: RGBA) {
        self.question = question; self.options = options; self.correct = correct
        self.accent = accent; self.textColor = textColor
    }
    /// Det som hamnar i .pptx och .pdf-anteckningar: frågan och alternativen som text.
    public var asText: String { ([question] + options.map { "• " + $0 }).joined(separator: "\n") }
}

public enum Content: Codable, Hashable, Sendable {
    case text(TextBox)
    case shape(ShapeBox)
    case image(ImageBox)
    case poll(PollBox)
}

/// Klickbara element (fas 3). Exporteras som PPTX-hyperlänkar.
public enum ElementLink: Codable, Hashable, Sendable {
    case nextSlide, previousSlide
    case slide(UUID)
    case url(URL)
}

/// Hur ett "visa när jag trycker"-element kommer in. Exporteras som klickanimation i .pptx.
public enum AppearEffect: String, Codable, CaseIterable, Sendable {
    case fade, pop, flyUp, flyFromLeft, flyFromRight
    /// Nya (protokoll 3). I .pptx: snurra och konfetti blir zoom, studsa blir flyg in uppifrån.
    case spin, bounce, confetti
}

public struct Element: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var frame: Frame
    /// Grader medurs.
    public var rotation: Double
    public var content: Content
    public var link: ElementLink?
    /// nil = syns direkt. Annars osynligt i presentationen tills den som presenterar trycker
    /// på det (eller trycker "nästa"), och då kommer det in med effekten.
    public var reveal: AppearEffect?
    /// Ljud (asset-id, .m4a/.wav) som spelas när man trycker på elementet i presentationen,
    /// eller när det visas om det har `reveal`. Exporteras som klickljud i .pptx.
    public var sound: String?
    /// true = försvinner när den som presenterar trycker på det (och kommer tillbaka vid nästa tryck).
    /// Exporteras inte: i .pptx står elementet kvar.
    public var vanish: Bool?
    public init(id: UUID = UUID(), frame: Frame, rotation: Double = 0, content: Content,
                link: ElementLink? = nil, reveal: AppearEffect? = nil, sound: String? = nil, vanish: Bool? = nil) {
        self.id = id; self.frame = frame; self.rotation = rotation; self.content = content
        self.link = link; self.reveal = reveal; self.sound = sound; self.vanish = vanish
    }
    public var vanishes: Bool { vanish == true }
    public var assetIDs: [String] {
        var ids: [String] = []
        if case .image(let i) = content { ids.append(i.assetID) }
        if let s = sound { ids.append(s) }
        return ids
    }
}

public enum DeckTransition: String, Codable, CaseIterable, Sendable { case none, fade, push, wipe }

public struct Slide: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var background: Fill
    public var elements: [Element]
    public var notes: String
    public var transition: DeckTransition
    public init(id: UUID = UUID(), background: Fill = .solid(.white), elements: [Element] = [],
                notes: String = "", transition: DeckTransition = .none) {
        self.id = id; self.background = background; self.elements = elements
        self.notes = notes; self.transition = transition
    }
    public func element(_ id: UUID) -> Element? { elements.first { $0.id == id } }
    /// Elementen som visas vid tryck, i den ordning "nästa" visar dem (bakifrån och fram).
    public var revealOrder: [UUID] { elements.filter { $0.reveal != nil }.map(\.id) }
    public var assetIDs: [String] {
        var ids = elements.flatMap(\.assetIDs)
        if case .image(let a) = background { ids.append(a) }
        return ids
    }
}

public struct Deck: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var slides: [Slide]
    public var modified: Date
    public init(id: UUID = UUID(), title: String, slides: [Slide] = [], modified: Date = Date()) {
        self.id = id; self.title = title; self.slides = slides; self.modified = modified
    }
    public func slideIndex(_ id: UUID) -> Int? { slides.firstIndex { $0.id == id } }
    public func slide(_ id: UUID) -> Slide? { slides.first { $0.id == id } }
    public var assetIDs: Set<String> { Set(slides.flatMap(\.assetIDs)) }
}
