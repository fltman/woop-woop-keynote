import Foundation
import Network

public enum Bonjour {
    public static let type = "_woopwoop._tcp"
    /// Apple TV-appar som kan visa en presentation.
    public static let tvType = "_woopwoop-tv._tcp"

    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let p = NWParameters(tls: nil, tcp: tcp)
        p.includePeerToPeer = true
        // Omstart efter paus binder samma port medan den gamla lyssnaren fortfarande stänger.
        p.allowLocalEndpointReuse = true
        return p
    }
}

/// En TCP-anslutning med längdprefixade JSON-meddelanden (4 byte big endian + JSON).
/// Allt körs på huvudkön så att meddelandena hanteras i den ordning de kom.
final class FramedConnection: @unchecked Sendable {
    let id = UUID()
    let connection: NWConnection
    var onReady: (() -> Void)?
    var onMessage: ((Wire) -> Void)?
    var onClose: ((String?) -> Void)?
    private var closed = false
    private var ready = false
    /// Så länge väntar vi på att nå den andra sidan. En värd som försvunnit (appen stängdes) kan
    /// annars lämna anslutningen hängande i "ansluter" för alltid.
    static let connectTimeout: TimeInterval = 8

    static let maxMessage = 64 * 1024 * 1024

    init(_ connection: NWConnection) { self.connection = connection }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.ready = true
                self.onReady?()
                self.readHeader()
            case .failed(let e):
                self.close("\(e)")
            case .waiting(let e):
                // Värden finns inte (längre). Ge upp i stället för att vänta för evigt.
                self.close("\(e)")
            case .cancelled:
                self.close(nil)
            default: break
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectTimeout) { [weak self] in
            guard let self, !self.ready else { return }
            self.close("ingen kontakt")
        }
    }

    func send(_ message: Wire) {
        guard !closed, let body = try? JSONEncoder().encode(message) else { return }
        var len = UInt32(body.count).bigEndian
        var frame = Data(bytes: &len, count: 4)
        frame.append(body)
        connection.send(content: frame, completion: .contentProcessed { [weak self] err in
            if let err { self?.close("\(err)") }
        })
    }

    /// Skicka ett sista meddelande och stäng först när det har gått iväg.
    func sendAndClose(_ message: Wire) {
        guard !closed, let body = try? JSONEncoder().encode(message) else { return cancel() }
        var len = UInt32(body.count).bigEndian
        var frame = Data(bytes: &len, count: 4)
        frame.append(body)
        connection.send(content: frame, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { [weak self] _ in self?.cancel() })
    }

    func cancel() {
        guard !closed else { return }
        connection.cancel()
    }

    private func close(_ reason: String?) {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose?(reason)
    }

    private func readHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, done, err in
            guard let self else { return }
            if let err { return self.close("\(err)") }
            guard let data, data.count == 4 else { return self.close(done ? nil : "trasigt huvud") }
            let len = data.withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }
            guard len > 0, len <= Self.maxMessage else { return self.close("för stort meddelande (\(len))") }
            self.readBody(len)
        }
    }

    private func readBody(_ len: Int) {
        connection.receive(minimumIncompleteLength: len, maximumLength: len) { [weak self] data, _, done, err in
            guard let self else { return }
            if let err { return self.close("\(err)") }
            guard let data, data.count == len else { return self.close(done ? nil : "avbrutet meddelande") }
            if let msg = try? JSONDecoder().decode(Wire.self, from: data) {
                self.onMessage?(msg)
            }
            if !self.closed { self.readHeader() }
        }
    }
}
