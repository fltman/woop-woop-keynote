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
    public init(isPresenting: Bool = false, slideIndex: Int = 0) {
        self.isPresenting = isPresenting; self.slideIndex = slideIndex
    }
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

    public static let protocolVersion = 1
}
