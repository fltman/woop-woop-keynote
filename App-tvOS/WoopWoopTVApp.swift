import SwiftUI
import SlideKit

@main
struct WoopWoopTVApp: App {
    var body: some Scene {
        WindowGroup { TVRoot() }
    }
}

/// TV:n är scenen: den hittar en presentation som delas, visar bygget live och presenterar.
/// Den redigerar aldrig (CONTRACT, "Vad det är").
@MainActor @Observable
final class TVModel {
    let browser = HostBrowser()
    var session: Session?
    let assets: AssetStore
    private let me: Peer

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        assets = AssetStore(directory: caches.appendingPathComponent("Assets"))
        let id = UserDefaults.standard.string(forKey: "peerID").flatMap(UUID.init) ?? UUID()
        UserDefaults.standard.set(id.uuidString, forKey: "peerID")
        me = Peer(id: id, name: "TV", color: RGBA(hex: "8E8E93"), role: .stage)
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.retryIfLost()
            }
        }
    }

    /// Presentationen TV:n visar (eller väntar på att få tillbaka).
    private(set) var wantedHost: String?
    /// Presentationer man aktivt lämnat med fjärren; dem hoppar TV:n inte in i igen av sig själv.
    private var declined: Set<String> = []

    func join(_ host: HostBrowser.Host) {
        session?.leave()
        let s = Session(deck: Deck(title: host.name), me: me, assets: assets)
        s.join(host.endpoint)
        session = s
        wantedHost = host.name
        declined.remove(host.name)
    }

    func leave() {
        if let w = wantedHost { declined.insert(w) }
        wantedHost = nil
        session?.leave()
        session = nil
    }

    private var isIdle: Bool {
        guard let s = session else { return true }
        if case .lost = s.link { return true }
        return false
    }

    /// Dela på telefonen = visa på TV:n. En ledig TV (eller en som tappat kontakten)
    /// tar den presentation som dök upp senast; en TV som visar något levande stannar kvar.
    func hostsChanged(old: [HostBrowser.Host], new: [HostBrowser.Host]) {
        guard isIdle else { return }
        if let w = wantedHost, let h = new.first(where: { $0.name == w }) { return join(h) }
        let added = new.filter { h in !old.contains { $0.name == h.name } }
        if let h = added.last { return join(h) }
        // TV:n startades när någon redan delade.
        let open = new.filter { !declined.contains($0.name) }
        if session == nil, open.count == 1 { join(open[0]) }
    }

    /// Försök igen med jämna mellanrum om kontakten tappats (t.ex. telefonen låstes).
    func retryIfLost() {
        guard let s = session, case .lost = s.link, let w = wantedHost,
              let h = browser.hosts.first(where: { $0.name == w }) else { return }
        join(h)
    }
}

struct TVRoot: View {
    @State private var model = TVModel()
    var body: some View {
        Group {
            if let s = model.session {
                if s.present.isPresenting && s.link == .connected {
                    TVPresent(session: s)
                } else {
                    StageView(session: s) { model.leave() }
                }
            } else {
                HostPicker(model: model)
            }
        }
        .onAppear { model.browser.start() }
        .onChange(of: model.browser.hosts) { old, hosts in
            #if DEBUG
            // -autojoin <namn>: bara presentationer vars namn innehåller <namn> (för simulatorn).
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-autojoin") {
                let want = i + 1 < args.count ? args[i + 1] : ""
                if model.session == nil, let h = hosts.first(where: { want.isEmpty || $0.name.contains(want) }) { model.join(h) }
                return
            }
            #endif
            model.hostsChanged(old: old, new: hosts)
        }
    }
}

struct HostPicker: View {
    let model: TVModel
    var body: some View {
        VStack(spacing: 50) {
            Text("Woop Woop").font(.system(size: 96, weight: .heavy, design: .rounded))
            if model.browser.hosts.isEmpty {
                VStack(spacing: 20) {
                    ProgressView()
                    Text("Letar efter presentationer…").font(.title2)
                    Text("Öppna en presentation på iPaden eller iPhonen och tryck på Dela.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Vilken presentation?").font(.title2).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 40) {
                        ForEach(model.browser.hosts) { h in
                            Button { model.join(h) } label: {
                                Label(h.name, systemImage: "rectangle.on.rectangle.angled")
                                    .font(.title2).padding(30)
                            }
                        }
                    }
                    .padding(40)
                }
            }
        }
    }
}
