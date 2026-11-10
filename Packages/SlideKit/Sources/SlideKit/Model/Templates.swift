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
        Theme(id: "neon", name: "Neon",
              background: .solid(RGBA(hex: "0B0B14")),
              title: TextStyle(font: .arial, size: 140, color: RGBA(hex: "39FF14"), bold: true),
              body: TextStyle(font: .arial, size: 60, color: RGBA(hex: "F2F2F2")),
              accent: RGBA(hex: "FF2E97")),
        Theme(id: "solnedgang", name: "Solnedgång",
              background: .gradient(from: RGBA(hex: "FF512F"), to: RGBA(hex: "F09819"), angle: 90),
              title: TextStyle(font: .trebuchet, size: 140, color: RGBA(hex: "FFFFFF"), bold: true),
              body: TextStyle(font: .trebuchet, size: 60, color: RGBA(hex: "FFF5E6")),
              accent: RGBA(hex: "2D1B4E")),
        Theme(id: "hav", name: "Hav",
              background: .gradient(from: RGBA(hex: "0F2027"), to: RGBA(hex: "2C5364"), angle: 90),
              title: TextStyle(font: .verdana, size: 132, color: RGBA(hex: "FFFFFF"), bold: true),
              body: TextStyle(font: .verdana, size: 60, color: RGBA(hex: "D6F5F5")),
              accent: RGBA(hex: "00D2D3")),
        Theme(id: "rymd", name: "Rymd",
              background: .gradient(from: RGBA(hex: "000000"), to: RGBA(hex: "1B1464"), angle: 45),
              title: TextStyle(font: .verdana, size: 132, color: RGBA(hex: "FFFFFF"), bold: true),
              body: TextStyle(font: .verdana, size: 60, color: RGBA(hex: "D9D4FF")),
              accent: RGBA(hex: "A55EEA")),
        Theme(id: "lava", name: "Lava",
              background: .gradient(from: RGBA(hex: "200122"), to: RGBA(hex: "6F0000"), angle: 90),
              title: TextStyle(font: .arial, size: 140, color: RGBA(hex: "FFA502"), bold: true),
              body: TextStyle(font: .arial, size: 60, color: RGBA(hex: "FFE8D6")),
              accent: RGBA(hex: "FF4757")),
        Theme(id: "pastell", name: "Pastell",
              background: .gradient(from: RGBA(hex: "A18CD1"), to: RGBA(hex: "FBC2EB"), angle: 45),
              title: TextStyle(font: .trebuchet, size: 140, color: RGBA(hex: "FFFFFF"), bold: true),
              body: TextStyle(font: .trebuchet, size: 60, color: RGBA(hex: "3B2A5C")),
              accent: RGBA(hex: "6C5CE7")),
        Theme(id: "mint", name: "Mint",
              background: .solid(RGBA(hex: "E8F8F5")),
              title: TextStyle(font: .trebuchet, size: 140, color: RGBA(hex: "117A65"), bold: true),
              body: TextStyle(font: .trebuchet, size: 60, color: RGBA(hex: "1C3D36")),
              accent: RGBA(hex: "1ABC9C")),
        Theme(id: "retro", name: "Retro",
              background: .solid(RGBA(hex: "F4E4C1")),
              title: TextStyle(font: .courier, size: 128, color: RGBA(hex: "3D405B"), bold: true),
              body: TextStyle(font: .courier, size: 56, color: RGBA(hex: "3D405B")),
              accent: RGBA(hex: "E07A5F")),
        Theme(id: "tidning", name: "Tidning",
              background: .solid(RGBA(hex: "FFFFFF")),
              title: TextStyle(font: .times, size: 150, color: RGBA(hex: "111111"), bold: true),
              body: TextStyle(font: .times, size: 62, color: RGBA(hex: "222222")),
              accent: RGBA(hex: "D63031")),
        Theme(id: "tavla", name: "Svarta tavlan",
              background: .solid(RGBA(hex: "264D3B")),
              title: TextStyle(font: .courier, size: 128, color: RGBA(hex: "FFFFFF"), bold: true),
              body: TextStyle(font: .courier, size: 56, color: RGBA(hex: "F1F5E9")),
              accent: RGBA(hex: "FFE66D")),
        Theme(id: "svart", name: "Svart",
              background: .solid(RGBA(hex: "111111")),
              title: TextStyle(font: .georgia, size: 140, color: RGBA(hex: "FFFFFF"), bold: true),
              body: TextStyle(font: .georgia, size: 60, color: RGBA(hex: "D0D0D0")),
              accent: RGBA(hex: "FFD32A")),
        Theme(id: "is", name: "Is",
              background: .gradient(from: RGBA(hex: "E0F7FF"), to: RGBA(hex: "FFFFFF"), angle: 90),
              title: TextStyle(font: .arial, size: 140, color: RGBA(hex: "0B3C5D"), bold: true),
              body: TextStyle(font: .arial, size: 60, color: RGBA(hex: "1D4E6B")),
              accent: RGBA(hex: "0984E3")),
        Theme(id: "ren", name: "Ren",
              background: .solid(.white),
              title: TextStyle(font: .arial, size: 140, color: .black, bold: true),
              body: TextStyle(font: .arial, size: 60, color: RGBA(hex: "333333")),
              accent: RGBA(hex: "0984E3")),
    ]
}

extension RGBA {
    /// Svart eller vitt, det som syns bäst ovanpå färgen.
    public var readableOn: RGBA { 0.299 * r + 0.587 * g + 0.114 * b > 0.6 ? RGBA(hex: "111111") : .white }
}

public enum SlideLayout: String, CaseIterable, Identifiable, Sendable {
    case title, titleAndText, bigWord, section, twoColumns, textAndPicture, bigPicture, threePictures, quote, bigNumber, versus, threeSteps, thanks, blank
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .title: "Rubrik"
        case .titleAndText: "Rubrik och text"
        case .bigWord: "Ett stort ord"
        case .section: "Nytt avsnitt"
        case .twoColumns: "Två spalter"
        case .textAndPicture: "Text och bild"
        case .bigPicture: "Stor bild"
        case .threePictures: "Tre bilder"
        case .quote: "Citat"
        case .bigNumber: "Stor siffra"
        case .versus: "Jämför två saker"
        case .threeSteps: "Tre steg"
        case .thanks: "Tack och frågor"
        case .blank: "Tom"
        }
    }

    public func makeSlide(theme: Theme) -> Slide {
        var s = Slide(background: theme.background)
        func text(_ t: String, _ style: TextStyle, _ f: Frame) -> Element {
            Element(frame: f, content: .text(TextBox(text: t, style: style)))
        }
        func shape(_ k: ShapeKind, _ f: Frame, _ c: RGBA) -> Element {
            Element(frame: f, content: .shape(ShapeBox(kind: k, fill: c)))
        }
        /// Rubrik överst till vänster, som de flesta bilder har.
        func heading(_ t: String) -> Element {
            var st = theme.title; st.size = 104
            return text(t, st, Frame(x: 120, y: 90, w: 1680, h: 150))
        }
        let onAccent = theme.accent.readableOn
        switch self {
        case .title:
            var t = theme.title; t.align = .center
            var b = theme.body; b.align = .center
            s.elements = [text("Rubrik", t, Frame(x: 160, y: 340, w: 1600, h: 200)),
                          text("Underrubrik", b, Frame(x: 160, y: 580, w: 1600, h: 100))]
        case .titleAndText:
            s.elements = [heading("Rubrik"),
                          text("• Första saken\n• Andra saken\n• Tredje saken", theme.body,
                               Frame(x: 120, y: 300, w: 1680, h: 660))]
        case .bigWord:
            var t = theme.title; t.size = 320; t.align = .center
            s.elements = [text("WOW", t, Frame(x: 60, y: 300, w: 1800, h: 420))]
        case .section:
            var t = theme.title; t.size = 160
            var b = theme.body; b.size = 56
            s.elements = [shape(.rectangle, Frame(x: 120, y: 330, w: 28, h: 420), theme.accent),
                          text("Del 1", b, Frame(x: 200, y: 330, w: 1500, h: 90)),
                          text("Nytt avsnitt", t, Frame(x: 200, y: 430, w: 1560, h: 320))]
        case .twoColumns:
            s.elements = [heading("Rubrik"),
                          text("• Vänster sida\n• En sak till", theme.body, Frame(x: 120, y: 300, w: 800, h: 660)),
                          text("• Höger sida\n• En sak till", theme.body, Frame(x: 1000, y: 300, w: 800, h: 660))]
        case .textAndPicture:
            s.elements = [heading("Rubrik"),
                          text("Berätta om bilden här.", theme.body, Frame(x: 120, y: 300, w: 820, h: 660)),
                          Element(frame: Frame(x: 1020, y: 300, w: 780, h: 600), content: .image(.placeholder))]
        case .bigPicture:
            var cap = theme.body; cap.align = .center
            s.elements = [Element(frame: Frame(x: 260, y: 80, w: 1400, h: 780), content: .image(.placeholder)),
                          text("Bildtext", cap, Frame(x: 160, y: 900, w: 1600, h: 100))]
        case .threePictures:
            var cap = theme.body; cap.align = .center; cap.size = 48
            s.elements = [heading("Rubrik")]
            for i in 0..<3 {
                let x = 120.0 + Double(i) * 580
                s.elements.append(Element(frame: Frame(x: x, y: 300, w: 520, h: 420), content: .image(.placeholder)))
                s.elements.append(text("Bildtext", cap, Frame(x: x, y: 750, w: 520, h: 90)))
            }
        case .quote:
            var q = theme.title; q.size = 96; q.italic = true; q.bold = false; q.align = .center
            var who = theme.body; who.align = .center
            var mark = theme.title; mark.size = 300; mark.color = theme.accent; mark.align = .center
            s.elements = [text("”", mark, Frame(x: 760, y: 60, w: 400, h: 300)),
                          text("Skriv ett citat som fastnar.", q, Frame(x: 200, y: 360, w: 1520, h: 320)),
                          text("– Vem sa det?", who, Frame(x: 200, y: 740, w: 1520, h: 100))]
        case .bigNumber:
            var n = theme.title; n.size = 400; n.align = .center; n.color = theme.accent
            var c = theme.body; c.align = .center; c.size = 72
            s.elements = [text("42", n, Frame(x: 60, y: 170, w: 1800, h: 500)),
                          text("Vad betyder siffran?", c, Frame(x: 160, y: 720, w: 1600, h: 120))]
        case .versus:
            var h = theme.title; h.size = 88; h.align = .center; h.color = onAccent
            var vs = theme.title; vs.size = 120; vs.align = .center
            var b = theme.body; b.align = .center
            s.elements = [shape(.roundedRectangle, Frame(x: 120, y: 160, w: 720, h: 420), theme.accent),
                          shape(.roundedRectangle, Frame(x: 1080, y: 160, w: 720, h: 420), theme.accent),
                          text("Den ena", h, Frame(x: 120, y: 310, w: 720, h: 130)),
                          text("Den andra", h, Frame(x: 1080, y: 310, w: 720, h: 130)),
                          text("VS", vs, Frame(x: 840, y: 290, w: 240, h: 170)),
                          text("Varför den är bäst", b, Frame(x: 120, y: 640, w: 720, h: 300)),
                          text("Varför den är bäst", b, Frame(x: 1080, y: 640, w: 720, h: 300))]
        case .threeSteps:
            var num = theme.title; num.size = 110; num.align = .center; num.color = onAccent
            var b = theme.body; b.align = .center; b.size = 52
            s.elements = [heading("Så går det till")]
            for i in 0..<3 {
                let x = 150.0 + Double(i) * 560
                s.elements.append(shape(.ellipse, Frame(x: x + 150, y: 320, w: 200, h: 200), theme.accent))
                s.elements.append(text("\(i + 1)", num, Frame(x: x + 150, y: 350, w: 200, h: 140)))
                s.elements.append(text(["Först", "Sedan", "Till sist"][i], b, Frame(x: x, y: 570, w: 500, h: 300)))
            }
            for i in 0..<2 {
                s.elements.append(shape(.arrow, Frame(x: 560.0 + Double(i) * 560, y: 385, w: 120, h: 70), theme.accent))
            }
        case .thanks:
            var t = theme.title; t.size = 280; t.align = .center
            var b = theme.body; b.align = .center; b.size = 72
            s.elements = [text("Tack!", t, Frame(x: 60, y: 250, w: 1800, h: 380)),
                          text("Har ni några frågor?", b, Frame(x: 160, y: 680, w: 1600, h: 120))]
        case .blank:
            break
        }
        return s
    }
}

/// Färdiga upplägg: några bilder att fylla i, så att man slipper börja från en tom sida.
public enum DeckTemplate: String, CaseIterable, Identifiable, Sendable {
    case empty, school, bookReview, topFive, quiz, aboutMe
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .empty: "Tom"
        case .school: "Skolarbete"
        case .bookReview: "Bokrecension"
        case .topFive: "Topp 5"
        case .quiz: "Quiz"
        case .aboutMe: "Om mig"
        }
    }
    public var symbol: String {
        switch self {
        case .empty: "rectangle"
        case .school: "graduationcap.fill"
        case .bookReview: "book.fill"
        case .topFive: "trophy.fill"
        case .quiz: "questionmark.circle.fill"
        case .aboutMe: "person.fill"
        }
    }

    public func makeDeck(theme: Theme) -> Deck {
        /// En bild ur en layout, med texterna utbytta i tur och ordning.
        func slide(_ l: SlideLayout, _ texts: [String], notes: String = "") -> Slide {
            var s = l.makeSlide(theme: theme)
            var i = 0
            for j in s.elements.indices {
                guard i < texts.count, case .text(var tb) = s.elements[j].content else { continue }
                tb.text = texts[i]; i += 1
                s.elements[j].content = .text(tb)
            }
            s.notes = notes
            return s
        }
        func question(_ q: String, _ options: [String], correct: Int) -> Slide {
            var s = Slide(background: theme.background)
            s.elements = [Element(frame: Frame(x: 210, y: 190, w: 1500, h: 700),
                                  content: .poll(PollBox(question: q, options: options, correct: correct,
                                                         accent: theme.accent, textColor: theme.body.color)))]
            return s
        }
        let slides: [Slide]
        let title: String
        switch self {
        case .empty:
            return Deck.new(theme: theme)
        case .school:
            title = "Mitt skolarbete"
            slides = [
                slide(.title, [title, "Av: ditt namn"]),
                slide(.titleAndText, ["Det här ska jag berätta om", "• Vad det är\n• Varför det är viktigt\n• Vad jag har lärt mig"]),
                slide(.textAndPicture, ["Vad är det?", "Förklara med egna ord."]),
                slide(.bigNumber, ["3", "En siffra som säger något viktigt"]),
                slide(.twoColumns, ["För och emot", "• En fördel\n• En till", "• En nackdel\n• En till"]),
                slide(.titleAndText, ["Källor", "• Var hittade du det här?\n• Böcker, webbsidor, personer"]),
                slide(.thanks, []),
            ]
        case .bookReview:
            title = "Bokrecension"
            slides = [
                slide(.title, ["Bokens titel", "Författare · recenserad av dig"]),
                slide(.textAndPicture, ["Vad handlar den om?", "Berätta utan att avslöja slutet."]),
                slide(.titleAndText, ["Personerna", "• Huvudpersonen\n• En viktig vän eller fiende\n• Den du gillade bäst"]),
                slide(.quote, ["”", "Ett citat ur boken som du minns.", "– sidan 42"]),
                slide(.bigNumber, ["4/5", "Mitt betyg, och varför"]),
                slide(.thanks, ["Läs den!", "Vem skulle gilla den här boken?"]),
            ]
        case .topFive:
            title = "Topp 5"
            slides = [slide(.title, ["Topp 5", "De bästa … någonsin"])]
                + (0..<5).map { i in slide(.section, ["Plats \(5 - i)", i == 4 ? "Vinnaren!" : "Vad är det?"]) }
                + [slide(.thanks, ["Håller ni med?", "Vad hade ni valt?"])]
        case .quiz:
            title = "Quiz"
            slides = [
                slide(.title, ["Quiz!", "Ta fram mobilen och skanna koden"]),
                question("Fråga 1: skriv din fråga här", ["Svar A", "Svar B", "Svar C"], correct: 0),
                question("Fråga 2", ["Svar A", "Svar B", "Svar C"], correct: 1),
                question("Fråga 3", ["Svar A", "Svar B", "Svar C", "Svar D"], correct: 2),
                slide(.thanks, ["Bra jobbat!", "Hur många rätt fick ni?"]),
            ]
        case .aboutMe:
            title = "Om mig"
            slides = [
                slide(.title, ["Det här är jag", "Ditt namn"]),
                slide(.textAndPicture, ["Vem är jag?", "Ålder, var du bor, vilka du bor med."]),
                slide(.threeSteps, ["Tre saker jag gillar", "1", "En sak", "2", "En till", "3", "Och en till"]),
                slide(.versus, ["Hund", "Katt", "VS", "Varför?", "Varför?"]),
                slide(.bigWord, ["HEJ!"]),
            ]
        }
        return Deck(title: title, slides: slides)
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
