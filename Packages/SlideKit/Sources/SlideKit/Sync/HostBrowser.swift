import Foundation
import Network
import Observation

/// Letar efter presentationer som delas på hemnätet.
@MainActor @Observable
public final class HostBrowser {
    public struct Host: Identifiable, Hashable {
        /// Presentationens fasta id (ur annonsen). Namnet kan ändras medan man delar.
        public var id: String
        public var name: String
        public var endpoint: NWEndpoint
        /// När delningen började (millisekunder sedan 1970), ur annonsen. Den senaste tar över.
        public var started: Double = 0
    }

    public private(set) var hosts: [Host] = []
    public private(set) var problem: String?
    @ObservationIgnored private var browser: NWBrowser?
    private let type: String

    /// Standard: presentationer som delas. `Bonjour.tvType`: Apple TV-appar.
    public init(type: String = Bonjour.type) { self.type = type }

    public func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: Bonjour.parameters())
        b.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                self?.hosts = results.compactMap { r in
                    guard case .service(let name, _, _, _) = r.endpoint else { return nil }
                    var key: String?, started = 0.0
                    if case .bonjour(let txt) = r.metadata { key = txt["id"]; started = txt["t"].flatMap(Double.init) ?? 0 }
                    return Host(id: key ?? name, name: name, endpoint: r.endpoint, started: started)
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
