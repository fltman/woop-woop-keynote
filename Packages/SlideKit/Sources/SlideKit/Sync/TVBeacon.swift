import Foundation
import Network

/// Gör en Apple TV synlig på hemnätet, så att telefonen kan erbjuda den när man trycker Spela,
/// och tar emot "visa den här presentationen".
@MainActor
public final class TVBeacon {
    private var listener: NWListener?
    private var connections: [FramedConnection] = []
    private let name: String
    public var onInvite: ((String) -> Void)?
    public private(set) var port: UInt16?

    public init(name: String) { self.name = name }

    public func start() {
        listener?.cancel()
        guard let l = try? NWListener(using: Bonjour.parameters()) else { return }
        l.service = NWListener.Service(name: name, type: Bonjour.tvType)
        l.newConnectionHandler = { [weak self] nw in
            MainActor.assumeIsolated {
                guard let self else { return }
                let c = FramedConnection(nw)
                self.connections.append(c)
                c.onMessage = { [weak self] m in
                    MainActor.assumeIsolated { if case .invite(let host) = m { self?.onInvite?(host) } }
                }
                c.onClose = { [weak self] _ in MainActor.assumeIsolated { self?.connections.removeAll { $0 === c } } }
                c.start()
            }
        }
        l.stateUpdateHandler = { [weak self] st in
            MainActor.assumeIsolated { if case .ready = st { self?.port = l.port?.rawValue } }
        }
        listener = l
        l.start(queue: .main)
    }

    public func stop() {
        listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }; connections.removeAll()
    }
}
