import Foundation

public enum PeerRole: String, Codable, Sendable { case editor, stage }

public struct Peer: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var color: RGBA
    public var role: PeerRole
    public init(id: UUID = UUID(), name: String, color: RGBA, role: PeerRole = .editor) {
        self.id = id; self.name = name; self.color = color; self.role = role
    }
    /// Färger som syns mot både ljusa och mörka bilder.
    public static let palette: [RGBA] = ["FF4757", "1E90FF", "2ED573", "FFA502", "A55EEA", "FF6B81", "00D2D3"]
        .map { RGBA(hex: $0) }
}

/// Ett element som någon drar i just nu, så att scenen kan visa rörelsen live
/// innan op:en skickas när fingret släpper.
public struct DragPreview: Codable, Hashable, Sendable {
    public var element: UUID
    public var frame: Frame
    public var rotation: Double
    public init(element: UUID, frame: Frame, rotation: Double) {
        self.element = element; self.frame = frame; self.rotation = rotation
    }
}

public struct Presence: Codable, Hashable, Sendable {
    public var peer: UUID
    public var slide: UUID?
    public var drag: DragPreview?
    public init(peer: UUID, slide: UUID? = nil, drag: DragPreview? = nil) {
        self.peer = peer; self.slide = slide; self.drag = drag
    }
}

public struct PresentState: Codable, Hashable, Sendable {
    public var isPresenting: Bool
    public var slideIndex: Int
    /// "Visa när jag trycker"-element som har visats på den aktuella bilden.
    public var revealed: [UUID]
    /// Senaste ljudet som ska spelas. Ny `nonce` = spela (igen); presentationsskärmen spelar det.
    public var sound: SoundCue?
    /// Element som den som presenterar har tryckt bort ("försvinner vid tryck") på den aktuella bilden.
    public var gone: [UUID]
    public init(isPresenting: Bool = false, slideIndex: Int = 0, revealed: [UUID] = [], sound: SoundCue? = nil, gone: [UUID] = []) {
        self.isPresenting = isPresenting; self.slideIndex = slideIndex; self.revealed = revealed; self.sound = sound; self.gone = gone
    }

    /// Det som inte syns på presentationsskärmen just nu på bild `slide`.
    public func hidden(on slide: Slide) -> Set<UUID> {
        Set(slide.revealOrder).subtracting(revealed).union(gone)
    }

    /// Tryck på ett element som försvinner vid tryck: bort, eller tillbaka om det redan är borta.
    public func togglingGone(_ id: UUID) -> PresentState {
        var s = self
        if let i = s.gone.firstIndex(of: id) { s.gone.remove(at: i) } else { s.gone.append(id) }
        return s
    }

    /// Nästa steg: visa nästa dolda element om det finns, annars nästa bild.
    public func next(in deck: Deck) -> PresentState {
        guard deck.slides.indices.contains(slideIndex) else { return self }
        if let id = deck.slides[slideIndex].revealOrder.first(where: { !revealed.contains($0) }) {
            return revealing(id, in: deck)
        }
        return going(to: slideIndex + 1, in: deck)
    }

    /// Förra bilden, färdigbyggd (som i Keynote).
    public func previous(in deck: Deck) -> PresentState { going(to: slideIndex - 1, in: deck) }

    /// Visar ett dolt element (och spelar dess ljud, om det har ett).
    public func revealing(_ id: UUID, in deck: Deck) -> PresentState {
        var s = self
        guard !s.revealed.contains(id) else { return s }
        s.revealed.append(id)
        if let e = deck.slides[safe: slideIndex]?.element(id), let snd = e.sound { s.sound = SoundCue(element: e.id, asset: snd) }
        return s
    }

    /// Spelar ett elements ljud (igen).
    public func playing(_ id: UUID, in deck: Deck) -> PresentState {
        var s = self
        if let snd = deck.slides[safe: slideIndex]?.element(id)?.sound { s.sound = SoundCue(element: id, asset: snd) }
        return s
    }

    /// Framåt: bilden börjar obyggd. Bakåt: färdigbyggd.
    public func going(to index: Int, in deck: Deck) -> PresentState {
        guard deck.slides.indices.contains(index), index != slideIndex else { return self }
        let built = index < slideIndex ? deck.slides[index].revealOrder : []
        return PresentState(isPresenting: isPresenting, slideIndex: index, revealed: built)
    }
}

public struct SoundCue: Codable, Hashable, Sendable {
    public var element: UUID
    public var asset: String
    public var nonce: UUID
    public init(element: UUID, asset: String, nonce: UUID = UUID()) {
        self.element = element; self.asset = asset; self.nonce = nonce
    }
}

extension Array {
    public subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

public enum RemoteCommand: String, Codable, Sendable { case next, previous, start, stop }

public struct LockEntry: Codable, Hashable, Sendable {
    public var element: UUID
    public var peer: UUID
}

/// Allt som går över nätet. Längdprefixad JSON över TCP (CONTRACT, arkitektur).
public enum Wire: Codable, Sendable {
    case hello(Peer, protocolVersion: Int)
    case welcome(deck: Deck, peers: [Peer], locks: [LockEntry], present: PresentState, lastEditedSlide: UUID?)
    case peers([Peer])
    /// Klient → värd. Värden svarar med commit (till alla) eller reject (till avsändaren).
    case submit(opID: UUID, Op)
    case commit(opID: UUID, Op, by: UUID)
    case reject(opID: UUID)
    /// Klient → värd: lås det här elementet (och släpp mitt förra). nil = släpp.
    case requestLock(UUID?)
    case locks([LockEntry])
    case presence(Presence)
    case presenceGone(UUID)
    case present(PresentState)
    case remote(RemoteCommand)
    case needAssets([String])
    case asset(id: String, data: Data)
    case bye(reason: String)
    /// Telefon → TV: "visa den här presentationen" (namnet den delas under).
    case invite(host: String)
    /// Det flyktiga under en presentation: reaktioner, laserpekare, ritade streck, ljudknappar, röster.
    case live(LiveEvent)

    public static let protocolVersion = 3
}

/// En punkt på bilden, i bildenheter.
public struct Spot: Codable, Hashable, Sendable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Ett streck som ritats ovanpå bilden under presentationen. Försvinner vid bildbyte.
public struct InkStroke: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var points: [Spot]
    public var color: RGBA
    public var width: Double
    public init(id: UUID = UUID(), points: [Spot], color: RGBA, width: Double = 10) {
        self.id = id; self.points = points; self.color = color; self.width = width
    }
}

public enum LiveEvent: Codable, Hashable, Sendable {
    /// Index i `LiveState.emoji`.
    case reaction(Int)
    case pointer(Spot?)
    /// Lägg till eller ersätt (strecket växer medan man ritar).
    case stroke(InkStroke)
    case clearInk
    case jingle(Jingle, nonce: UUID)
    /// Bara från värden: ställningen i en omröstning.
    case votes(poll: UUID, counts: [Int])
    /// Visa eller göm rätt svar i ett quiz.
    case answer(poll: UUID, shown: Bool)
    /// Bara från värden: adressen publiken röstar på (QR-koden). nil = ingen.
    case audience(url: String?)
}

public struct Reaction: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var emoji: String
    public var at = Date()
    /// 0…1, var på bredden den flyger upp.
    public var lane = Double.random(in: 0.08...0.92)
}

/// Allt flyktigt som alla ser under en presentation. Sparas aldrig.
public struct LiveState: Equatable, Sendable {
    public static let emoji = ["😂", "👏", "🔥", "❤️", "😮", "🎉"]
    public static let reactionTime: TimeInterval = 3.2

    public var reactions: [Reaction] = []
    public var pointer: Spot?
    public var ink: [InkStroke] = []
    public var jingle: Jingle?
    public var jingleNonce: UUID?
    public var votes: [UUID: [Int]] = [:]
    public var answers: Set<UUID> = []
    public var audienceURL: String?
    public init() {}

    mutating func apply(_ e: LiveEvent) {
        switch e {
        case .reaction(let i):
            guard Self.emoji.indices.contains(i) else { return }
            let now = Date()
            reactions.removeAll { now.timeIntervalSince($0.at) > Self.reactionTime }
            if reactions.count < 40 { reactions.append(Reaction(emoji: Self.emoji[i])) }
        case .pointer(let p): pointer = p
        case .stroke(let s):
            if let i = ink.firstIndex(where: { $0.id == s.id }) { ink[i] = s } else if ink.count < 200 { ink.append(s) }
        case .clearInk: ink = []
        case .jingle(let j, let n): jingle = j; jingleNonce = n
        case .votes(let p, let c): votes[p] = c
        case .answer(let p, let shown): if shown { answers.insert(p) } else { answers.remove(p) }
        case .audience(let u): audienceURL = u
        }
    }
}
