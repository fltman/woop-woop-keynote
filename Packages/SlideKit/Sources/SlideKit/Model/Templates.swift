import Foundation

/// Teman: färger och typsnitt som nya bilder får. Ett tema är bara en startpunkt;
/// det sparas inte i decket (allt som syns ligger i elementen, CONTRACT §2).
public struct Theme: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var background: Fill
    public var title: TextStyle
    public var body: TextStyle
    public var accent: RGBA

    public static let all: [Theme] = [
        Theme(id: "natt", name: "Natt",
              background: .gradient(from: RGBA(hex: "1B1464"), to: RGBA(hex: "6F1E51"), angle: 90),
              title: TextStyle(font: .trebuchet, size: 144, color: .white, bold: true),
              body: TextStyle(font: .trebuchet, size: 64, color: RGBA(hex: "F5E6FF")),
              accent: RGBA(hex: "FFC312")),
        Theme(id: "papper", name: "Papper",
              background: .solid(RGBA(hex: "FBF7EF")),
              title: TextStyle(font: .georgia, size: 140, color: RGBA(hex: "2D3436"), bold: true),
              body: TextStyle(font: .georgia, size: 60, color: RGBA(hex: "2D3436")),
              accent: RGBA(hex: "D63031")),
        Theme(id: "godis", name: "Godis",
              background: .gradient(from: RGBA(hex: "FD79A8"), to: RGBA(hex: "FDCB6E"), angle: 45),
              title: TextStyle(font: .verdana, size: 136, color: .white, bold: true),
              body: TextStyle(font: .verdana, size: 60, color: .white),
              accent: RGBA(hex: "6C5CE7")),
        Theme(id: "skog", name: "Skog",
              background: .solid(RGBA(hex: "0B3D2E")),
              title: TextStyle(font: .arial, size: 140, color: RGBA(hex: "C7F464"), bold: true),
              body: TextStyle(font: .arial, size: 60, color: RGBA(hex: "E8F5E9")),
              accent: RGBA(hex: "C7F464")),
        Theme(id: "ren", name: "Ren",
              background: .solid(.white),
              title: TextStyle(font: .arial, size: 140, color: .black, bold: true),
              body: TextStyle(font: .arial, size: 60, color: RGBA(hex: "333333")),
              accent: RGBA(hex: "0984E3")),
    ]
}

public enum SlideLayout: String, CaseIterable, Identifiable, Sendable {
    case title, titleAndText, bigWord, blank
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .title: "Rubrik"
        case .titleAndText: "Rubrik och text"
        case .bigWord: "Ett stort ord"
        case .blank: "Tom"
        }
    }

    public func makeSlide(theme: Theme) -> Slide {
        var s = Slide(background: theme.background)
        func text(_ t: String, _ style: TextStyle, _ f: Frame) -> Element {
            Element(frame: f, content: .text(TextBox(text: t, style: style)))
        }
        switch self {
        case .title:
            var t = theme.title; t.align = .center
            var b = theme.body; b.align = .center
            s.elements = [text("Rubrik", t, Frame(x: 160, y: 340, w: 1600, h: 200)),
                          text("Underrubrik", b, Frame(x: 160, y: 580, w: 1600, h: 100))]
        case .titleAndText:
            var t = theme.title; t.size = 104
            s.elements = [text("Rubrik", t, Frame(x: 120, y: 90, w: 1680, h: 150)),
                          text("• Första saken\n• Andra saken\n• Tredje saken", theme.body,
                               Frame(x: 120, y: 300, w: 1680, h: 660))]
        case .bigWord:
            var t = theme.title; t.size = 320; t.align = .center
            s.elements = [text("WOW", t, Frame(x: 60, y: 300, w: 1800, h: 420))]
        case .blank:
            break
        }
        return s
    }
}

extension Deck {
    public static func new(title: String = "Ny presentation", theme: Theme = Theme.all[0]) -> Deck {
        var s = SlideLayout.title.makeSlide(theme: theme)
        if case .text(var tb) = s.elements[0].content {
            tb.text = title
            s.elements[0].content = .text(tb)
        }
        return Deck(title: title, slides: [s])
    }
}
