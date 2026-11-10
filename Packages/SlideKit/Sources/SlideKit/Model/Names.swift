import Foundation

// Svenska namn som både appen och scenens händelseflöde använder.

extension ShapeKind {
    public var name: String {
        switch self {
        case .rectangle: "Rektangel"
        case .roundedRectangle: "Rundad rektangel"
        case .ellipse: "Cirkel"
        case .triangle: "Triangel"
        case .star: "Stjärna"
        case .arrow: "Pil"
        case .heart: "Hjärta"
        }
    }
    public var symbol: String {
        switch self {
        case .rectangle: "rectangle.fill"
        case .roundedRectangle: "app.fill"
        case .ellipse: "circle.fill"
        case .triangle: "triangle.fill"
        case .star: "star.fill"
        case .arrow: "arrow.right"
        case .heart: "heart.fill"
        }
    }
    /// (obestämd, bestämd): "en stjärna", "stjärnan".
    var forms: (String, String) {
        switch self {
        case .rectangle: ("en rektangel", "rektangeln")
        case .roundedRectangle: ("en rundad rektangel", "den rundade rektangeln")
        case .ellipse: ("en cirkel", "cirkeln")
        case .triangle: ("en triangel", "triangeln")
        case .star: ("en stjärna", "stjärnan")
        case .arrow: ("en pil", "pilen")
        case .heart: ("ett hjärta", "hjärtat")
        }
    }
}

extension Content {
    /// "ett foto" och inte "en bild", så att det inte blandas ihop med bilderna i presentationen.
    var forms: (String, String) {
        switch self {
        case .text: ("en text", "texten")
        case .image(let i): i.isPlaceholder ? ("en bildplats", "bildplatsen") : ("ett foto", "fotot")
        case .shape(let s): s.kind.forms
        case .poll(let p): p.correct == nil ? ("en omröstning", "omröstningen") : ("en quizfråga", "quizfrågan")
        }
    }
}

extension AppearEffect {
    public var name: String {
        switch self {
        case .fade: "Tona in"
        case .pop: "Poppa upp"
        case .flyUp: "Flyg in nerifrån"
        case .flyFromLeft: "Flyg in från vänster"
        case .flyFromRight: "Flyg in från höger"
        case .spin: "Snurra in"
        case .bounce: "Studsa ner"
        case .confetti: "Konfetti"
        }
    }
}

extension DeckTransition {
    public var name: String {
        switch self { case .none: "Ingen"; case .fade: "Tona"; case .push: "Skjut"; case .wipe: "Svep" }
    }
}

extension Element {
    /// "stjärnan", "texten", "fotot": så att presentatören får veta vad nästa tryck visar.
    public var definiteName: String { content.forms.1 }
}
