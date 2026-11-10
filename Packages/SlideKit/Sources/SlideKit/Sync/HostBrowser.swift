import Foundation
import Network
import Observation

/// Letar efter presentationer som delas på hemnätet.
@MainActor @Observable
public final class HostBrowser {
    public struct Host: Identifiable, Hashable {
        public var id: String { name }
        public var name: String
        public var endpoint: NWEndpoint
    }

    public private(set) var hosts: [Host] = []
    public private(set) var problem: String?
    @ObservationIgnored private var browser: NWBrowser?

    public init() {}

    public func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: Bonjour.type, domain: nil), using: Bonjour.parameters())
        b.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                self?.hosts = results.compactMap { r in
                    guard case .service(let name, _, _, _) = r.endpoint else { return nil }
                    return Host(name: name, endpoint: r.endpoint)
                }.sorted { $0.name < $1.name }
            }
        }
        b.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed(let e), .waiting(let e): self?.problem = "\(e)"
                case .ready: self?.problem = nil
                default: break
                }
            }
        }
        browser = b
        b.start(queue: .main)
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        hosts = []
    }
}
