import Foundation
import Network

/// En pytteliten webbserver hos den som delar. Publiken skannar QR-koden på TV:n och får en sida
/// där de röstar och skickar reaktioner. Allt stannar på hemnätet (CONTRACT §8, §16).
@MainActor
final class AudienceServer {
    /// Det publiken ser just nu (JSON), givet väljarens id.
    var state: (_ voter: String, _ name: String?) -> Data = { _, _ in Data("{}".utf8) }
    var vote: (_ poll: UUID, _ option: Int, _ voter: String, _ name: String?) -> Void = { _, _, _, _ in }
    var buzz: (_ voter: String, _ name: String?) -> Void = { _, _ in }
    var ask: (_ text: String, _ voter: String, _ name: String?) -> Void = { _, _, _ in }
    var react: (Int) -> Void = { _ in }
    var onReady: (UInt16) -> Void = { _ in }

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    func start() {
        stop()
        guard let l = try? NWListener(using: .tcp) else { return }
        l.newConnectionHandler = { [weak self] c in MainActor.assumeIsolated { self?.accept(c) } }
        l.stateUpdateHandler = { [weak self] st in
            MainActor.assumeIsolated { if case .ready = st, let p = l.port?.rawValue { self?.onReady(p) } }
        }
        listener = l
        l.start(queue: .main)
    }

    func stop() {
        listener?.cancel(); listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func accept(_ c: NWConnection) {
        let key = ObjectIdentifier(c)
        connections[key] = c
        c.stateUpdateHandler = { [weak self] st in
            MainActor.assumeIsolated {
                switch st {
                case .failed, .cancelled: self?.connections[key] = nil
                default: break
                }
            }
        }
        c.start(queue: .main)
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                guard let self, let data, let head = String(data: data, encoding: .utf8) else { return c.cancel() }
                let (status, type, body) = self.respond(to: head)
                var out = Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
                out.append(body)
                c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
            }
        }
    }

    /// Bara GET, och bara fyra adresser. Allt annat är 404.
    func respond(to head: String) -> (String, String, Data) {
        let parts = (head.components(separatedBy: "\r\n").first ?? "").split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET", let c = URLComponents(string: String(parts[1])) else {
            return ("404 Not Found", "text/plain", Data())
        }
        func q(_ name: String) -> String? { c.queryItems?.first { $0.name == name }?.value }
        let voter = String((q("voter") ?? "").prefix(64))
        let name = q("name")
        switch c.path {
        case "/":
            return ("200 OK", "text/html; charset=utf-8", Data(Self.page.utf8))
        case "/state":
            return ("200 OK", "application/json", state(voter, name))
        case "/vote":
            if let p = q("poll").flatMap(UUID.init), let o = q("option").flatMap(Int.init), !voter.isEmpty { vote(p, o, voter, name) }
            return ("200 OK", "application/json", state(voter, name))
        case "/buzz":
            if !voter.isEmpty { buzz(voter, name) }
            return ("200 OK", "application/json", state(voter, name))
        case "/ask":
            if let t = q("q"), !voter.isEmpty { ask(t, voter, name) }
            return ("200 OK", "application/json", Data("{}".utf8))
        case "/react":
            if let e = q("e").flatMap(Int.init) { react(e) }
            return ("200 OK", "application/json", Data("{}".utf8))
        default:
            return ("404 Not Found", "text/plain", Data())
        }
    }

    static let page = """
    <!doctype html><html lang="sv"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
    <title>Woop Woop</title>
    <style>
    body{margin:0;font-family:-apple-system,system-ui,sans-serif;background:#1b1464;color:#fff;
      min-height:100vh;display:flex;flex-direction:column;align-items:center;padding:20px 16px;box-sizing:border-box}
    h1{font-size:20px;margin:0 0 12px;opacity:.7}
    h2{font-size:26px;text-align:center;margin:8px 0 20px}
    #me{display:flex;gap:8px;align-items:center;margin-bottom:14px;width:100%;max-width:480px}
    input{font:inherit;font-size:18px;padding:12px;border-radius:12px;border:0;flex:1;min-width:0}
    #score{font-weight:700;white-space:nowrap}
    #opts{width:100%;max-width:480px;display:flex;flex-direction:column;gap:12px}
    button{font:inherit;border:0;border-radius:16px;color:#fff;cursor:pointer}
    .opt{font-size:20px;font-weight:600;padding:18px;background:rgba(255,255,255,.14);text-align:left}
    .opt.mine{background:#ffc312;color:#1b1464}
    .opt.right{outline:4px solid #2ed573}
    .opt.wrong{opacity:.45}
    #wait{font-size:20px;opacity:.75;text-align:center;margin:30px 0}
    #msg{min-height:28px;margin:16px 0;font-size:18px;font-weight:600;text-align:center}
    #buzz{display:none;width:220px;height:220px;border-radius:50%;background:#ff4757;font-size:44px;font-weight:800;
      margin:20px 0;box-shadow:0 10px 0 #b3202d}
    #buzz:active{transform:translateY(8px);box-shadow:0 2px 0 #b3202d}
    #askbox{display:flex;gap:8px;width:100%;max-width:480px;margin-top:22px}
    #send{background:#ffc312;color:#1b1464;font-weight:700;padding:0 16px}
    #emoji{margin-top:auto;padding-top:24px;display:flex;gap:10px;flex-wrap:wrap;justify-content:center}
    .emo{font-size:34px;width:64px;height:64px;background:rgba(255,255,255,.12)}
    .emo:active{transform:scale(1.25)}
    </style></head><body>
    <h1>Woop Woop</h1>
    <div id="me"><input id="name" placeholder="Vad heter du?" maxlength="20"><span id="score"></span></div>
    <div id="wait">Väntar på en fråga …</div>
    <button id="buzz">BUZZ!</button>
    <h2 id="q" hidden></h2><div id="opts"></div><div id="msg"></div>
    <div id="askbox"><input id="ask" placeholder="Ställ en fråga till den som presenterar" maxlength="200"><button id="send">Skicka</button></div>
    <div id="emoji"></div>
    <script>
    let voter=localStorage.getItem('voter');
    if(!voter){voter=Math.random().toString(36).slice(2)+Date.now().toString(36);localStorage.setItem('voter',voter)}
    const E=['😂','👏','🔥','❤️','😮','🎉'],$=id=>document.getElementById(id);
    $('name').value=localStorage.getItem('name')||'';
    $('name').oninput=()=>localStorage.setItem('name',$('name').value);
    const who=()=>'voter='+voter+'&name='+encodeURIComponent($('name').value.trim());
    E.forEach((e,i)=>{const b=document.createElement('button');b.className='emo';b.textContent=e;
      b.onclick=()=>fetch('/react?e='+i);$('emoji').appendChild(b)});
    $('buzz').onclick=()=>fetch('/buzz?'+who()).then(r=>r.json()).then(show);
    $('send').onclick=()=>{const t=$('ask').value.trim();if(!t)return;
      fetch('/ask?'+who()+'&q='+encodeURIComponent(t));$('ask').value='';$('msg').textContent='Frågan är skickad!'};
    function show(s){
      const p=s.poll;
      $('score').textContent=s.points?('⭐ '+s.points+(s.rank?'  ·  plats '+s.rank:'')):'';
      $('buzz').style.display=s.buzzer&&!p?'block':'none';
      $('wait').hidden=!!p||s.buzzer;$('q').hidden=!p;
      if(!p){$('opts').innerHTML='';
        if(s.winner)$('msg').textContent=s.winner+' var först!';
        return}
      $('q').textContent=p.question;$('opts').innerHTML='';
      p.options.forEach((o,i)=>{const b=document.createElement('button');b.className='opt';b.textContent=o;
        if(p.mine===i)b.classList.add('mine');
        if(p.shown&&p.correct!=null)b.classList.add(i===p.correct?'right':'wrong');
        b.onclick=()=>fetch('/vote?poll='+p.id+'&option='+i+'&'+who()).then(r=>r.json()).then(show);
        $('opts').appendChild(b)});
      $('msg').textContent=p.shown&&p.correct!=null&&p.mine!=null?(p.mine===p.correct?'Rätt! 🎉':'Inte den här gången.')
        :(p.mine!=null?'Tack! Du kan byta tills svaret visas.':'');
    }
    function tick(){fetch('/state?'+who()).then(r=>r.json()).then(show).catch(()=>{})}
    tick();setInterval(tick,1200);
    </script></body></html>
    """
}

/// Enhetens adress på hemnätet (wifi), för QR-koden.
enum LocalAddress {
    static func ipv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var found: [String: String] = [:]
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  a.ifa_flags & UInt32(IFF_UP) != 0, a.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                found[String(cString: a.ifa_name)] = String(cString: host)
            }
        }
        // en0 är wifi på iPhone och iPad; annars första bästa som inte är mobilnätet.
        return found["en0"] ?? found.filter { !$0.key.hasPrefix("pdp_ip") }.sorted { $0.key < $1.key }.first?.value
    }
}
