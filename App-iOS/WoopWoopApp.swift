import SwiftUI
import SlideKit

@main
struct WoopWoopApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: phase) { _, p in model.scenePhaseChanged(p) }
                .onChange(of: model.browser.hosts) { _, _ in model.rejoinIfLost(); model.yieldToNewerShare() }
                #if DEBUG
                .task { if Demo.requested { Demo.run(model) } }
                #endif
        }
    }
}

/// Vem jag är på den här enheten. Namnet och färgen syns för de andra och på TV:n.
struct Profile: Codable, Equatable {
    var id = UUID()
    var name = ""
    var colorIndex = 0
    var peer: Peer { Peer(id: id, name: name, color: Peer.palette[colorIndex % Peer.palette.count]) }

    static func load() -> Profile {
        guard let d = UserDefaults.standard.data(forKey: "profile"),
              let p = try? JSONDecoder().decode(Profile.self, from: d) else { return Profile() }
        return p
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "profile") }
}

@MainActor @Observable
final class AppModel {
    let library = Library()
    var profile = Profile.load() { didSet { profile.save() } }
    /// Presentationen som är öppen i editorn.
    var session: Session?
    let browser = HostBrowser()
    /// Apple TV-appar på hemnätet, som Spela kan erbjuda.
    let tvs = HostBrowser(type: Bonjour.tvType)
    /// Presentationen jag gått med i, så att jag kan ansluta igen efter ett avbrott.
    private var joinedHost: String?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var wasInBackground = false
    private let keeper = BackgroundKeeper()

    init() {
        browser.start()
        tvs.start()
        // Försök igen var tredje sekund om kontakten med den som delar har tappats.
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.rejoinIfLost()
            }
        }
    }

    /// iOS pausar appen i bakgrunden (skärmlås, annan app, fjärren). BackgroundKeeper håller den vaken
    /// upp till en kvart; därefter pausas den, och delningen startar om när appen är framme.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            wasInBackground = true
            // Delar vi eller är med i en delning: håll appen vaken (upp till en kvart).
            if let s = session, s.role != .solo { keeper.start() }
            guard session?.role == .host, backgroundTask == .invalid else { return }
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Dela") { [weak self] in self?.endBackgroundTask() }
        case .active:
            // Fick appen köra hela tiden lever delningen: rör den inte. Annars (pausad av iOS) gör om den.
            let alive = keeper.isRunning && session?.link == .connected
            keeper.stop()
            endBackgroundTask()
            if wasInBackground && !alive { session?.resumeHosting() }
            wasInBackground = false
            rejoinIfLost()
        default: break
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// Någon annan började dela efter mig: då tar den delningen över och min avslutas (CONTRACT §9).
    var takeover: String?
    func yieldToNewerShare() {
        guard let s = session, s.role == .host, let mine = s.sharedAt else { return }
        let t = mine.timeIntervalSince1970 * 1000
        guard let newer = browser.hosts.filter({ $0.id != s.shareKey && $0.started > t }).max(by: { $0.started < $1.started }) else { return }
        s.stopHosting(reason: "\(newer.name) visas nu i stället")
        takeover = newer.name
    }

    func rejoinIfLost() {
        guard let s = session, s.role == .solo, !s.turnedAway, case .lost = s.link, let name = joinedHost,
              let h = browser.hosts.first(where: { $0.id == name }) else { return }
        join(h)
    }

    func open(_ deck: Deck) {
        close()
        let s = Session(deck: deck, me: profile.peer, assets: library.assets)
        s.onChange = { [library] d in library.save(d) }
        session = s
    }

    func join(_ host: HostBrowser.Host) {
        close()
        let s = Session(deck: Deck(title: host.name), me: profile.peer, assets: library.assets)
        s.join(host.endpoint)
        session = s
        joinedHost = host.id
    }

    func close() {
        joinedHost = nil
        guard let s = session else { return }
        s.select(nil)
        if s.role == .host { library.flush(); s.stopHosting() }
        if s.role == .client { s.leave() }
        library.flush()
        session = nil
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.profile.name.isEmpty {
            ProfileSetup()
        } else if let s = model.session {
            EditorView(session: s)
        } else {
            LibraryView()
        }
    }
}

struct ProfileSetup: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var color = 0
    var body: some View {
        VStack(spacing: 28) {
            Text("Woop Woop").font(.system(size: 56, weight: .heavy, design: .rounded))
            Text("Vad heter du?").font(.title2)
            TextField("Namn", text: $name)
                .textFieldStyle(.roundedBorder).font(.title2).frame(maxWidth: 360)
                .submitLabel(.done)
            ColorRow(selected: $color)
            Button("Kör!") {
                model.profile.name = name.trimmingCharacters(in: .whitespaces)
                model.profile.colorIndex = color
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }
}

struct ColorRow: View {
    @Binding var selected: Int
    var body: some View {
        HStack(spacing: 14) {
            ForEach(Peer.palette.indices, id: \.self) { i in
                Circle().fill(Peer.palette[i].color)
                    .frame(width: 44, height: 44)
                    .overlay { if i == selected { Circle().stroke(.primary, lineWidth: 4).padding(-6) } }
                    .onTapGesture { selected = i }
                    .accessibilityLabel("Färg \(i + 1)")
                    .accessibilityAddTraits(i == selected ? .isSelected : [])
            }
        }
    }
}
