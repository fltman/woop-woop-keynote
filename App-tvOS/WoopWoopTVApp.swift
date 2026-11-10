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
        beacon.onInvite = { [weak self] name in self?.invited(name) }
        beacon.start()
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.retryIfLost()
                self?.updateIdleTimer()
            }
        }
    }

    /// Gör TV:n synlig för telefonerna (Spela → välj den här TV:n).
    private let beacon = TVBeacon(name: UIDevice.current.name)
    /// Någon bad just den här TV:n visa en presentation som ännu inte syns på nätet.
    private var pendingInvite: String?
    /// Senaste gången något hände. Står TV:n och väntar längre än så får skärmsläckaren komma.
    private var lastActivity = Date()
    static let stayAwakeWhileWaiting: TimeInterval = 60 * 60

    /// Presentationen TV:n visar (eller väntar på att få tillbaka).
    private(set) var wantedHost: String?
    /// När den delningen började. En delning som börjat senare tar över.
    private var wantedStarted = 0.0
    /// Varför TV:n gick tillbaka till väntläget (t.ex. "Värden slutade dela").
    private(set) var notice: String?
    /// Presentationer man aktivt lämnat med fjärren; dem hoppar TV:n inte in i igen av sig själv.
    private var declined: Set<String> = []

    /// Telefonen valde den här TV:n: visa presentationen även om vi visar något annat.
    func invited(_ key: String) {
        lastActivity = Date()
        declined.remove(key)
        if let h = browser.hosts.first(where: { $0.id == key }) { join(h) } else { pendingInvite = key }
        updateIdleTimer()
    }

    /// Skärmsläckaren startar aldrig medan något delas, och inte under den första timmen när TV:n väntar.
    /// (Ingen app kan stänga en skärmsläckare som redan är igång eller väcka en sovande Apple TV.)
    func updateIdleTimer() {
        let connected = session.map { s in if case .lost = s.link { return false } else { return true } } ?? false
        if connected { lastActivity = Date() }
        UIApplication.shared.isIdleTimerDisabled = connected || Date().timeIntervalSince(lastActivity) < Self.stayAwakeWhileWaiting
    }

    func becameActive() {
        lastActivity = Date()
        beacon.start()
        updateIdleTimer()
    }

    func join(_ host: HostBrowser.Host) {
        lastActivity = Date()
        pendingInvite = nil
        notice = nil
        session?.leave()
        let s = Session(deck: Deck(title: host.name), me: me, assets: assets)
        s.join(host.endpoint)
        session = s
        wantedHost = host.id
        wantedStarted = host.started
        declined.remove(host.id)
    }

    func leave() {
        if let w = wantedHost { declined.insert(w) }
        wantedHost = nil; wantedStarted = 0
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
        if let p = pendingInvite, let h = new.first(where: { $0.id == p }) { return join(h) }
        // Den senaste delningen tar över, även om TV:n visar något annat (CONTRACT §9).
        let now = Date()
        let newest = new.filter { h in
            h.id != wantedHost && h.started > wantedStarted && !declined.contains(h.id)
                && (cooldown[h.id].map { now.timeIntervalSince($0) > 15 } ?? true)
        }.max { $0.started < $1.started }
        if let newest { return join(newest) }
        guard isIdle else { return }
        if let w = wantedHost, let h = new.first(where: { $0.id == w }) { return join(h) }
        // Jämför på presentationens fasta id: ett namnbyte är inte en ny presentation.
        let added = new.filter { h in !old.contains { $0.id == h.id } }
        if let h = added.last { return join(h) }
        // TV:n startades när någon redan delade.
        joinOnlyOpenHost(new)
    }

    /// När värden sa adjö: presentationens id och när, så att vi inte försöker igen direkt.
    private var cooldown: [String: Date] = [:]
    /// Antal kontroller i rad (var tredje sekund) där presentationen vi väntar på inte har synts.
    private var missing = 0

    private func joinOnlyOpenHost(_ hosts: [HostBrowser.Host]) {
        let now = Date()
        let open = hosts.filter { h in
            !declined.contains(h.id) && cooldown[h.id].map { now.timeIntervalSince($0) > 15 } ?? true
        }
        if session == nil, open.count == 1 { join(open[0]) }
    }

    /// Försök igen med jämna mellanrum om kontakten tappats (t.ex. telefonen låstes).
    func retryIfLost() {
        // Värden sa adjö (slutade dela, fel version): tillbaka till väntläget i stället för att
        // stå kvar med en död scen eller försöka om och om igen.
        if let s = session, s.turnedAway, case .lost(let why) = s.link {
            notice = why
            // Vänta en stund innan samma presentation prövas igen (annonsen kan hänga kvar ett tag,
            // och vid olika appversioner ska vi inte fråga om var tredje sekund). Men spärra den inte:
            // delar telefonen samma presentation igen ska TV:n visa den.
            if let w = wantedHost { cooldown[w] = Date() }
            wantedHost = nil; wantedStarted = 0; session = nil
            return
        }
        // Ledig TV och precis en presentation delas: visa den. Händelsen "ny presentation" kan utebli
        // när samma presentation slutar delas och delas igen i ett svep.
        if session == nil { joinOnlyOpenHost(browser.hosts) }
        guard let s = session, case .lost = s.link, let w = wantedHost else { return }
        if let h = browser.hosts.first(where: { $0.id == w }) { missing = 0; return join(h) }
        // Presentationen vi väntar på delas inte längre. Finns det precis en annan, ta den efter en
        // liten stund; annars vänta en halv minut och gå sedan till väntläget.
        missing += 1
        let others = browser.hosts.filter { !declined.contains($0.id) }
        if missing >= 3, others.count == 1 { missing = 0; return join(others[0]) }
        // Telefonen hålls numera vaken i bakgrunden, så en presentation som varit borta i en halv minut
        // är troligen stängd på riktigt (t.ex. appen sveptes bort utan att hinna säga adjö).
        if missing >= 10 {
            missing = 0
            notice = "Presentationen delas inte längre"
            wantedHost = nil; wantedStarted = 0; session = nil
        }
    }
}

struct TVRoot: View {
    @State private var model = TVModel()
    @Environment(\.scenePhase) private var phase
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
        .onChange(of: phase) { _, p in if p == .active { model.becameActive() } }
        // Den som delade stängde sin presentation: tillbaka till väntläget direkt, utan att vänta på nästa kontroll.
        .onChange(of: model.session?.turnedAway) { _, away in if away == true { model.retryIfLost() } }
        .onChange(of: model.session?.link) { _, _ in if model.session?.turnedAway == true { model.retryIfLost() } }
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
    @State private var music = WaitingMusic()
    @Environment(\.scenePhase) private var phase
    @FocusState private var focused: Bool
    var body: some View {
        ZStack {
            WaitingBackground()
            VStack {
                Spacer()
                Label(music.muted ? "Play/paus sätter på musiken" : "Play/paus stänger av musiken",
                      systemImage: music.muted ? "speaker.slash.fill" : "playpause.fill")
                    .font(.callout).foregroundStyle(.white.opacity(0.6)).padding(.bottom, 30)
            }
            VStack(spacing: 44) {
                HStack(spacing: 50) {
                    LogoCards().scaleEffect(0.75).frame(width: 400, height: 280)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Woop Woop").font(.system(size: 120, weight: .heavy, design: .rounded))
                        Text(model.browser.hosts.isEmpty ? "Scenen är ledig. Vem börjar?" : "Vilken presentation vill ni se?")
                            .font(.system(size: 40, weight: .semibold)).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                }
                if let n = model.notice {
                    Label(n, systemImage: "info.circle.fill").font(.title3.bold())
                        .padding(.horizontal, 28).padding(.vertical, 14)
                        .foregroundStyle(.black).background(Color(red: 1, green: 0.76, blue: 0.07), in: Capsule())
                }
                if model.browser.hosts.isEmpty {
                    HowToSteps()
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 40) {
                            ForEach(model.browser.hosts) { h in
                                Button { model.join(h) } label: {
                                    Label(h.name, systemImage: "play.rectangle.fill")
                                        .font(.title2.bold()).padding(30)
                                }
                            }
                        }
                        .padding(40)
                    }
                }
            }
            .padding(60)
        }
        .focusable(model.browser.hosts.isEmpty)
        .focused($focused)
        .onPlayPauseCommand { music.muted.toggle() }
        .onAppear { focused = true; music.start() }
        .onDisappear { music.stop() }
        .onChange(of: phase) { _, p in p == .active ? music.start() : music.stop() }
    }
}
