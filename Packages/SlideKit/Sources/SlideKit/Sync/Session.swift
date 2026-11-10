import Foundation
import Network
import Observation

/// En öppen presentation: ensam, som värd eller som klient. Appen pratar bara med Session.
///
/// Värden bestämmer ordningen (CONTRACT §3): klienten visar `confirmed` + sina egna `pending`.
/// Värden skickar varje commit till alla, även avsändaren, som då stryker sin pending-op.
@MainActor @Observable
public final class Session {
    public enum Role: Equatable { case solo, host, client }
    public enum Link: Equatable { case none, connecting, connected, lost(String) }

    public private(set) var role: Role = .solo
    public private(set) var link: Link = .none
    /// Värden sa adjö (nej tack, slutade dela, fel version). Då ska ingen ansluta igen av sig själv:
    /// annars frågar ett "Nej" om igen var tredje sekund.
    public private(set) var turnedAway = false
    public private(set) var me: Peer
    /// Det som visas: bekräftat + mina väntande ändringar.
    public private(set) var deck: Deck
    public private(set) var peers: [Peer] = []
    /// element → peer
    public private(set) var locks: [UUID: UUID] = [:]
    public private(set) var presence: [UUID: Presence] = [:]
    public private(set) var present = PresentState() {
        didSet {
            // Streck och pekare hör till bilden de ritades på.
            if oldValue.slideIndex != present.slideIndex || oldValue.isPresenting != present.isPresenting {
                live.ink = []; live.pointer = nil
            }
        }
    }
    /// Reaktioner, laserpekare, streck, ljudknappar och röster. Flyktigt, sparas aldrig.
    public private(set) var live = LiveState()
    public private(set) var lastEditedSlide: UUID?
    /// Bilden där något senast hände (ändring, bildbyte, markering, drag). Scenen följer den.
    public private(set) var focusSlide: UUID?
    /// Händelseflödet, nyast sist.
    public private(set) var activity: [Activity] = []
    /// element → senaste ändring, så att scenen kan låta det lysa upp.
    public private(set) var recentEdits: [UUID: RecentEdit] = [:]
    /// Ändras varje gång en bild kommer in från nätet, så att vyer ritar om.
    public private(set) var assetVersion = 0
    public let assets: AssetStore

    /// Anropas när decket ändrats och bör sparas (ensam eller värd).
    @ObservationIgnored public var onChange: ((Deck) -> Void)?

    @ObservationIgnored private var confirmed: Deck
    @ObservationIgnored private var pending: [(id: UUID, op: Op)] = []
    @ObservationIgnored private var undoStack: [Op] = []
    @ObservationIgnored private var redoStack: [Op] = []
    @ObservationIgnored private var mySelection: UUID?
    @ObservationIgnored private var lastCoalesce: (key: String, at: Date)?
    @ObservationIgnored private var requestedAssets: Set<String> = []

    // Värd
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var clients: [UUID: FramedConnection] = [:]   // conn.id → anslutning
    @ObservationIgnored private var clientPeer: [UUID: UUID] = [:]            // conn.id → peer.id
    // Klient
    @ObservationIgnored private var upstream: FramedConnection?

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public private(set) var hostPort: UInt16?
    /// Redigerare som väntar på att värden ska släppa in dem. TV:n (scen) kommer in direkt.
    public private(set) var joinRequests: [Peer] = []
    /// Släpp in redigerare först efter värdens ja. Av i tester.
    @ObservationIgnored public var requireApproval = true
    @ObservationIgnored private var waiting: [UUID: (cid: UUID, peer: Peer)] = [:]   // peer.id → anslutning
    /// Den som släppts in en gång kommer in direkt igen efter ett avbrott.
    @ObservationIgnored private var admitted: Set<UUID> = []

    public init(deck: Deck, me: Peer, assets: AssetStore) {
        self.deck = deck
        self.confirmed = deck
        self.me = me
        self.assets = assets
        self.peers = [me]
    }

    // MARK: - Ändringar

    /// Gör en ändring. Returnerar false om den inte är tillåten (låst av någon annan).
    /// `coalesce`: ändringar med samma nyckel inom 1,5 s blir ett enda ångra-steg
    /// (en hel skrivning eller ett helt reglagedrag i stället för varje bokstav).
    @discardableResult
    public func perform(_ op: Op, undoable: Bool = true, coalesce: String? = nil) -> Bool {
        if let e = op.elementID, let owner = locks[e], owner != me.id { return false }
        guard let inverse = deck.inverse(of: op) else { return false }
        guard submit(op) else { return false }
        let now = Date()
        defer { lastCoalesce = coalesce.map { ($0, now) } }
        if let key = coalesce, let last = lastCoalesce, last.key == key, now.timeIntervalSince(last.at) < 1.5 {
            return true
        }
        if undoable {
            undoStack.append(inverse)
            if undoStack.count > 200 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        return true
    }

    public func undo() { lastCoalesce = nil; step(from: &undoStack, to: &redoStack) }
    public func redo() { step(from: &redoStack, to: &undoStack) }

    private func step(from: inout [Op], to: inout [Op]) {
        while let op = from.popLast() {
            if let e = op.elementID, let owner = locks[e], owner != me.id { continue }
            guard let inv = deck.inverse(of: op) else { continue }
            if submit(op) { to.append(inv); return }
        }
    }

    private func submit(_ op: Op) -> Bool {
        var test = deck
        guard test.apply(op) else { return false }
        switch role {
        case .solo:
            commitLocally(op, by: me.id)
        case .host:
            hostCommit(op, opID: UUID(), by: me.id, from: nil)
        case .client:
            let id = UUID()
            pending.append((id, op))
            deck = test
            sendMissingAssets(for: op)
            upstream?.send(.submit(opID: id, op))
        }
        return true
    }

    private func commitLocally(_ op: Op, by: UUID) {
        let before = confirmed
        confirmed.apply(op)
        note(op, by: by, before: before)
        confirmed.modified = Date()
        deck = confirmed
        if let s = op.slideID, confirmed.slideIndex(s) != nil { lastEditedSlide = s }
        clampPresent()
        if case .setTitle = op, role == .host, advertising { listener?.service = serviceName }
        onChange?(confirmed)
    }

    private func rebuildView() {
        var v = confirmed
        for p in pending { v.apply(p.op) }
        deck = v
    }

    // MARK: - Markering, närvaro, presentation

    /// Markerar ett element (låser det åt mig) eller avmarkerar (nil).
    public func select(_ element: UUID?) {
        mySelection = element
        switch role {
        case .solo: locks = element.map { [$0: me.id] } ?? [:]
        case .host: hostLock(element, peer: me.id)
        case .client: upstream?.send(.requestLock(element))
        }
    }

    public func isLockedByOther(_ element: UUID) -> Peer? {
        guard let p = locks[element], p != me.id else { return nil }
        return peers.first { $0.id == p }
    }

    public func setPresence(slide: UUID?, drag: DragPreview? = nil) {
        let p = Presence(peer: me.id, slide: slide, drag: drag)
        guard presence[me.id] != p else { return }
        follow(p)
        presence[me.id] = p
        switch role {
        case .solo: break
        case .host: broadcast(.presence(p))
        case .client: upstream?.send(.presence(p))
        }
    }

    public func setPresent(_ s: PresentState) {
        switch role {
        case .solo: present = s; clampPresent()
        case .host: present = s; clampPresent(); broadcast(.present(present))
        case .client: upstream?.send(.present(s))
        }
    }

    public func remote(_ cmd: RemoteCommand) {
        switch role {
        case .client: upstream?.send(.remote(cmd))
        default: applyRemote(cmd)
        }
    }

    // MARK: - Live: reaktioner, pekare, streck, ljudknappar, röster

    /// Skickar något flyktigt till alla. Syns direkt hos mig själv.
    public func send(_ e: LiveEvent) {
        switch e {
        case .votes, .audience: guard role != .client else { return }
        default: break
        }
        applyLive(e)
        switch role {
        case .solo: break
        case .host: broadcast(.live(e))
        case .client: upstream?.send(.live(e))
        }
    }

    private func applyLive(_ e: LiveEvent) {
        live.apply(e)
        if case .reaction = e {
            // Städa när de har flugit klart, så att vyerna kan sluta rita.
            DispatchQueue.main.asyncAfter(deadline: .now() + LiveState.reactionTime + 0.2) { [weak self] in
                MainActor.assumeIsolated {
                    let now = Date()
                    self?.live.reactions.removeAll { now.timeIntervalSince($0.at) > LiveState.reactionTime }
                }
            }
        }
    }

    /// Omröstningen publiken kan rösta i just nu: den första synliga på bilden som presenteras.
    public var currentPoll: (id: UUID, box: PollBox)? {
        guard present.isPresenting, let slide = confirmed.slides[safe: present.slideIndex] else { return nil }
        let hidden = present.hidden(on: slide)
        for e in slide.elements where !hidden.contains(e.id) {
            if case .poll(let p) = e.content { return (e.id, p) }
        }
        return nil
    }

    /// En röst från publikens webbsida. En röst per person; man får byta tills rätt svar visas.
    func castVote(poll: UUID, option: Int, voter: String) {
        guard let cur = currentPoll, cur.id == poll, cur.box.options.indices.contains(option),
              !live.answers.contains(poll) else { return }
        ballots[poll, default: [:]][voter] = option
        var counts = [Int](repeating: 0, count: cur.box.options.count)
        for o in ballots[poll, default: [:]].values where counts.indices.contains(o) { counts[o] += 1 }
        send(.votes(poll: poll, counts: counts))
    }

    /// Det publikens sida visar (JSON).
    func audienceState(voter: String) -> Data {
        var poll: Any = NSNull()
        if let cur = currentPoll {
            let shown = live.answers.contains(cur.id)
            var p: [String: Any] = ["id": cur.id.uuidString, "question": cur.box.question, "options": cur.box.options, "shown": shown]
            if let mine = ballots[cur.id]?[voter] { p["mine"] = mine }
            if shown, let c = cur.box.correct { p["correct"] = c }
            poll = p
        }
        return (try? JSONSerialization.data(withJSONObject: ["poll": poll])) ?? Data("{}".utf8)
    }

    @ObservationIgnored private var ballots: [UUID: [String: Int]] = [:]
    @ObservationIgnored private var audience: AudienceServer?

    private func startAudience() {
        let a = audience ?? AudienceServer()
        audience = a
        a.state = { [weak self] v in self?.audienceState(voter: v) ?? Data("{}".utf8) }
        a.vote = { [weak self] p, o, v in self?.castVote(poll: p, option: o, voter: v) }
        a.react = { [weak self] i in self?.send(.reaction(i)) }
        a.onReady = { [weak self] port in
            self?.send(.audience(url: LocalAddress.ipv4().map { "http://\($0):\(port)" }))
        }
        a.start()
    }

    private func stopAudience() {
        audience?.stop(); audience = nil
        applyLive(.audience(url: nil))
    }

    private func applyRemote(_ cmd: RemoteCommand) {
        var s = present
        switch cmd {
        case .next: s = present.next(in: confirmed)
        case .previous: s = present.previous(in: confirmed)
        case .start: s.isPresenting = true; s.revealed = []
        case .stop: s.isPresenting = false
        }
        setPresent(s)
    }

    private func clampPresent() {
        let maxIndex = max(confirmed.slides.count - 1, 0)
        present.slideIndex = min(max(present.slideIndex, 0), maxIndex)
    }

    public func rename(_ name: String) { me.name = name }

    // MARK: - Det som händer (scenen följer det)

    private func note(_ op: Op, by: UUID, before: Deck) {
        let now = Date()
        if let s = op.slideID, confirmed.slideIndex(s) != nil { focusSlide = s }
        if let e = op.elementID {
            recentEdits = recentEdits.filter { now.timeIntervalSince($0.value.at) < 5 }
            recentEdits[e] = RecentEdit(peer: by, at: now)
        }
        let name = peers.first { $0.id == by }?.name ?? "Någon"
        guard let (text, key) = Activity.describe(op, before: before, name: name) else { return }
        if let last = activity.last, last.peer == by, last.key == key, now.timeIntervalSince(last.at) < 4 {
            activity[activity.count - 1].text = text
            activity[activity.count - 1].at = now
        } else {
            activity.append(Activity(id: UUID(), peer: by, slide: op.slideID, text: text, at: now, key: key))
            if activity.count > 8 { activity.removeFirst(activity.count - 8) }
        }
    }

    /// Någon bytte bild eller drar i något: dit tittar scenen.
    private func follow(_ p: Presence) {
        guard let s = p.slide else { return }
        if p.drag != nil || presence[p.peer]?.slide != s { focusSlide = s }
    }

    /// Någon markerade något nytt: dit tittar scenen.
    private func followNewLocks(_ new: [UUID: UUID]) {
        for (e, _) in new where locks[e] == nil {
            if let s = confirmed.slides.first(where: { $0.element(e) != nil }) { focusSlide = s.id }
        }
    }

    // MARK: - Värd

    /// Börjar dela presentationen på hemnätet. `advertise: false` används i tester.
    public func startHosting(advertise: Bool = true, port: UInt16 = 0) throws {
        guard role == .solo else { return }
        advertising = advertise
        try makeListener(port: port)
        role = .host
        link = .connecting
        startAudience()
        if let sel = mySelection { locks = [sel: me.id] }
    }

    /// Startar om delningen efter att iOS har pausat appen (skärmlås, annan app, fjärren).
    /// Anslutningar som överlevde behålls; lyssnaren och Bonjour-annonsen görs om.
    public func resumeHosting() {
        guard role == .host else { return }
        link = .connecting
        retries = 0
        startAudience()
        guard let old = listener else { return relisten() }
        listener = nil
        // Porten släpps först när den gamla lyssnaren stängt helt; starta den nya då.
        old.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { MainActor.assumeIsolated { self?.relisten() } }
        }
        old.cancel()
    }

    @ObservationIgnored private var retries = 0
    private func relisten() {
        guard role == .host, listener == nil else { return }
        do { try makeListener(port: hostPort ?? 0) } catch { link = .lost("Kunde inte dela igen: \(error)") }
    }

    private func makeListener(port: UInt16) throws {
        let l = try NWListener(using: Bonjour.parameters(), on: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!)
        if advertising { l.service = serviceName }
        l.newConnectionHandler = { [weak self] c in
            MainActor.assumeIsolated { self?.accept(c) }
        }
        l.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    guard self.listener === l else { return }
                    self.retries = 0
                    self.hostPort = l.port?.rawValue; self.link = .connected
                case .waiting(let e):
                    // Vanligast: appen har inte fått använda lokalt nätverk.
                    self.link = .lost("Kan inte dela (\(e)). Slå på Woop Woop under Inställningar → Integritet och säkerhet → Lokalt nätverk.")
                case .failed:
                    // T.ex. när iOS pausat appen. Vi är fortfarande värd: försök igen några gånger,
                    // och resumeHosting() när appen kommer fram igen.
                    guard self.listener === l else { return }
                    self.listener = nil
                    self.link = .lost("Delningen pausades. Den startar igen när appen är framme.")
                    if self.retries < 5 {
                        self.retries += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { self.relisten() } }
                    }
                default: break
                }
            }
        }
        listener = l
        l.start(queue: .main)
    }

    @ObservationIgnored private var advertising = false

    /// Namnet presentationen delas under på hemnätet.
    public var advertisedName: String { serviceName.name ?? "" }
    /// Presentationens fasta id i annonsen. Namnet kan bytas medan man delar; id:t består,
    /// så TV:n och de andra hittar tillbaka efter ett avbrott.
    public var shareKey: String { confirmed.id.uuidString }

    /// Ber en Apple TV visa den här presentationen. Delar först om vi inte redan gör det.
    public func invite(tv endpoint: NWEndpoint) {
        if role == .solo { try? startHosting() }
        guard role == .host else { return }
        let c = FramedConnection(NWConnection(to: endpoint, using: Bonjour.parameters()))
        let key = shareKey
        c.onReady = { c.sendAndClose(.invite(host: key)) }
        invites.append(c)
        c.onClose = { [weak self] _ in MainActor.assumeIsolated { self?.invites.removeAll { $0 === c } } }
        c.start()
    }
    @ObservationIgnored private var invites: [FramedConnection] = []
    private var serviceName: NWListener.Service {
        // Bonjour-namn får vara högst 63 byte.
        var name = "\(me.name): \(deck.title)"
        while name.utf8.count > 63 { name.removeLast() }
        var txt = NWTXTRecord()
        txt["id"] = shareKey
        return NWListener.Service(name: name, type: Bonjour.type, txtRecord: txt)
    }

    public func stopHosting() {
        guard role == .host else { return }
        waiting.removeAll(); joinRequests.removeAll(); admitted.removeAll()
        for c in clients.values { c.sendAndClose(.bye(reason: "Värden slutade dela")) }
        clients.removeAll(); clientPeer.removeAll()
        listener?.cancel(); listener = nil
        stopAudience()
        role = .solo; link = .none; hostPort = nil
        peers = [me]
        locks = locks.filter { $0.value == me.id }
        presence = presence.filter { $0.key == me.id }
    }

    private func accept(_ nw: NWConnection) {
        let c = FramedConnection(nw)
        clients[c.id] = c
        c.onMessage = { [weak self, cid = c.id] m in MainActor.assumeIsolated { self?.hostReceive(m, from: cid) } }
        c.onClose = { [weak self, cid = c.id] _ in MainActor.assumeIsolated { self?.dropClient(cid) } }
        c.start()
    }

    private func dropClient(_ cid: UUID) {
        clients[cid] = nil
        if let w = waiting.first(where: { $0.value.cid == cid }) {
            waiting[w.key] = nil
            joinRequests.removeAll { $0.id == w.key }
        }
        guard let pid = clientPeer.removeValue(forKey: cid) else { return }
        peers.removeAll { $0.id == pid }
        locks = locks.filter { $0.value != pid }
        presence[pid] = nil
        broadcast(.peers(peers))
        broadcast(.locks(lockEntries))
        broadcast(.presenceGone(pid))
    }

    /// Värdens svar på en förfrågan om att få vara med och redigera.
    public func answer(_ peerID: UUID, admit yes: Bool) {
        joinRequests.removeAll { $0.id == peerID }
        guard let w = waiting.removeValue(forKey: peerID), let c = clients[w.cid] else { return }
        if yes { admit(w.peer, cid: w.cid) } else { c.sendAndClose(.bye(reason: "\(me.name) släppte inte in dig")) }
    }

    private func admit(_ peer: Peer, cid: UUID) {
        guard let c = clients[cid] else { return }
        admitted.insert(peer.id)
        // Samma person ansluter igen innan vi märkt att den gamla anslutningen dog. Pensionera den
        // gamla först, annars plockar dess stängning bort personen ur listan fast hen är kvar.
        for (old, p) in clientPeer where p == peer.id && old != cid {
            clientPeer[old] = nil
            clients.removeValue(forKey: old)?.cancel()
        }
        clientPeer[cid] = peer.id
        peers.removeAll { $0.id == peer.id }
        peers.append(peer)
        c.send(.welcome(deck: confirmed, peers: peers, locks: lockEntries, present: present, lastEditedSlide: lastEditedSlide))
        for p in presence.values { c.send(.presence(p)) }
        c.send(.live(.audience(url: live.audienceURL)))
        for (p, counts) in live.votes { c.send(.live(.votes(poll: p, counts: counts))) }
        for p in live.answers { c.send(.live(.answer(poll: p, shown: true))) }
        for s in live.ink { c.send(.live(.stroke(s))) }
        broadcast(.peers(peers), except: cid)
    }

    private var lockEntries: [LockEntry] { locks.map { LockEntry(element: $0.key, peer: $0.value) } }

    private func hostReceive(_ m: Wire, from cid: UUID) {
        guard let c = clients[cid] else { return }
        if case .hello(var peer, let v) = m {
            guard v == Wire.protocolVersion else { c.sendAndClose(.bye(reason: "Olika versioner av appen")); return }
            // Två med samma färg är förvirrande på scenen: ge en ledig färg.
            let used = Set(peers.map(\.color))
            if used.contains(peer.color), let free = Peer.palette.first(where: { !used.contains($0) }) { peer.color = free }
            if requireApproval && peer.role == .editor && !admitted.contains(peer.id) {
                waiting[peer.id] = (cid, peer)
                joinRequests.removeAll { $0.id == peer.id }
                joinRequests.append(peer)
            } else {
                admit(peer, cid: cid)
            }
            return
        }
        guard let pid = clientPeer[cid] else { return }  // inget före hello
        switch m {
        case .submit(let opID, let op):
            if let e = op.elementID, let owner = locks[e], owner != pid {
                c.send(.reject(opID: opID))
            } else if !hostCommit(op, opID: opID, by: pid, from: cid) {
                c.send(.reject(opID: opID))
            }
        case .requestLock(let e):
            hostLock(e, peer: pid)
        case .presence(var p):
            p.peer = pid
            follow(p)
            presence[pid] = p
            broadcast(.presence(p), except: cid)
        case .present(let s):
            setPresent(s)
        case .remote(let cmd):
            applyRemote(cmd)
        case .needAssets(let ids):
            for id in ids where !id.contains("/") { if let d = assets.data(id) { c.send(.asset(id: id, data: d)) } }
        case .asset(let id, let data):
            receiveAsset(id, data)
        case .live(let e):
            // Röster och adressen kommer bara från värden.
            switch e { case .votes, .audience: return; default: break }
            applyLive(e)
            broadcast(.live(e), except: cid)
        default: break
        }
    }

    @discardableResult
    private func hostCommit(_ op: Op, opID: UUID, by: UUID, from: UUID?) -> Bool {
        var test = confirmed
        guard test.apply(op) else { return false }
        commitLocally(op, by: by)
        broadcast(.commit(opID: opID, op, by: by))
        return true
    }

    private func hostLock(_ element: UUID?, peer: UUID) {
        var l = locks.filter { $0.value != peer }
        if let e = element, l[e] == nil { l[e] = peer }
        guard l != locks else { return }
        followNewLocks(l)
        locks = l
        broadcast(.locks(lockEntries))
    }

    private func broadcast(_ m: Wire, except: UUID? = nil) {
        for (cid, c) in clients where cid != except && clientPeer[cid] != nil { c.send(m) }
    }

    // MARK: - Klient

    /// Ansluter till en värd. Mitt eget deck byts mot värdens när välkomsten kommer.
    public func join(_ endpoint: NWEndpoint) {
        leave()
        let c = FramedConnection(NWConnection(to: endpoint, using: Bonjour.parameters()))
        upstream = c
        role = .client
        link = .connecting
        c.onReady = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                c.send(.hello(self.me, protocolVersion: Wire.protocolVersion))
            }
        }
        c.onMessage = { [weak self] m in MainActor.assumeIsolated { self?.clientReceive(m) } }
        c.onClose = { [weak self] reason in
            MainActor.assumeIsolated {
                guard let self, self.upstream === c else { return }
                self.upstream = nil
                self.role = .solo
                self.pending.removeAll()
                self.rebuildView()
                self.peers = [self.me]
                self.locks = [:]
                self.presence = [:]
                self.live = LiveState()
                // Ett avsked från värden (bye) har redan sagt varför; skriv inte över det.
                // Råa nätverksfel (POSIX 54 …) säger ingenting för en elvaåring.
                if case .lost = self.link {} else { self.link = .lost("Tappade kontakten med den som delar") }
            }
        }
        c.start()
    }

    public func leave() {
        guard let c = upstream else { return }
        upstream = nil
        c.cancel()
        role = .solo; link = .none
        pending.removeAll(); rebuildView()
        peers = [me]; locks = [:]; presence = [:]; live = LiveState()
    }

    private func clientReceive(_ m: Wire) {
        switch m {
        case .welcome(let d, let ps, let ls, let pr, let last):
            confirmed = d
            pending.removeAll()
            undoStack.removeAll(); redoStack.removeAll()
            rebuildView()
            peers = ps
            if let mine = ps.first(where: { $0.id == me.id }) { me = mine }
            locks = Dictionary(ls.map { ($0.element, $0.peer) }, uniquingKeysWith: { a, _ in a })
            present = pr
            lastEditedSlide = last
            focusSlide = last
            link = .connected
            fetchMissingAssets()
            if let sel = mySelection { upstream?.send(.requestLock(sel)) }
        case .peers(let ps):
            peers = ps
            if let mine = ps.first(where: { $0.id == me.id }) { me = mine }
        case .commit(let opID, let op, let by):
            let before = confirmed
            confirmed.apply(op)
            note(op, by: by, before: before)
            if let i = pending.firstIndex(where: { $0.id == opID }) { pending.remove(at: i) }
            rebuildView()
            if let s = op.slideID, confirmed.slideIndex(s) != nil { lastEditedSlide = s }
            clampPresent()
            fetchMissingAssets()
        case .reject(let opID):
            pending.removeAll { $0.id == opID }
            rebuildView()
        case .locks(let ls):
            let l = Dictionary(ls.map { ($0.element, $0.peer) }, uniquingKeysWith: { a, _ in a })
            followNewLocks(l)
            locks = l
        case .presence(let p):
            follow(p)
            presence[p.peer] = p
        case .presenceGone(let id):
            presence[id] = nil
        case .present(let s):
            present = s
            clampPresent()
        case .asset(let id, let data):
            receiveAsset(id, data)
        case .needAssets(let ids):
            for id in ids where !id.contains("/") { if let d = assets.data(id) { upstream?.send(.asset(id: id, data: d)) } }
        case .live(let e):
            applyLive(e)
        case .bye(let reason):
            turnedAway = true
            link = .lost(reason)
        default: break
        }
    }

    private func fetchMissingAssets() {
        let missing = deck.assetIDs.filter { !assets.has($0) && !requestedAssets.contains($0) }
        guard !missing.isEmpty else { return }
        requestedAssets.formUnion(missing)
        upstream?.send(.needAssets(Array(missing)))
    }

    /// En ny bild ska finnas hos värden innan op:en som använder den kommer fram.
    private func sendMissingAssets(for op: Op) {
        var ids: [String] = []
        switch op {
        case .upsertElement(_, let e, _): ids = e.assetIDs
        case .insertSlide(let s, _): ids = s.assetIDs
        case .setSlideProps(_, .image(let a), _, _): ids = [a]
        default: break
        }
        for id in ids where !confirmed.assetIDs.contains(id) {
            if let d = assets.data(id) { upstream?.send(.asset(id: id, data: d)) }
        }
    }

    private func receiveAsset(_ id: String, _ data: Data) {
        // Innehållsadresserat: lita bara på bytes som matchar sitt namn.
        let ext = (id as NSString).pathExtension
        guard AssetStore.id(for: data, ext: ext) == id else { return }
        _ = try? assets.put(data, id: id)
        requestedAssets.remove(id)
        assetVersion += 1
    }
}
