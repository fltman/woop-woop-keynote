import SwiftUI
import AVFoundation
import SlideKit

/// Väntläget: TV:n är på och väntar på att någon ska dela. Ska kännas som en scen före föreställningen,
/// inte som en felskärm. Galna presentationsbilder kommer flygande inifrån och ut, förbi tittaren.
struct WaitingBackground: View {
    static let slides = ["kapybara", "katter", "laxor", "mandag", "sent", "somn", "tacos", "wifi"].map { "slide-\($0)" }
    /// Så lång tid tar en bild från mitten till utanför kanten.
    static let period = 14.0

    private struct Flyer: Identifiable { let id: Int; let name: String; let u: Double; let angle: Double; let tilt: Double }

    /// Var varje bild är just nu. Riktningen byts för varje varv, så att det inte ser likadant ut.
    private static func flyers(at t: Double) -> [Flyer] {
        slides.indices.map { i in
            let raw = t / period + Double(i) / Double(slides.count)
            let cycle = floor(raw), u = raw - cycle
            var rng = SplitMixTV(seed: UInt64(i) &* 7919 &+ UInt64(max(cycle, 0)) &* 104729)
            // Åt sidorna hellre än rakt upp eller ner: där finns mest plats på en bred skärm.
            let side = rng.unit() < 0.5 ? 0.0 : Double.pi
            let angle = side + (rng.unit() - 0.5) * 1.5
            return Flyer(id: i, name: slides[i], u: u, angle: angle, tilt: (rng.unit() - 0.5) * 40)
        }
        .sorted { $0.u < $1.u }   // de närmaste (störst) ritas överst
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.11, green: 0.08, blue: 0.39), Color(red: 0.44, green: 0.12, blue: 0.32)],
                           startPoint: .top, endPoint: .bottom)
            // 30 rutor i sekunden: åtta bilder som flyttas och skalas klarar även Apple TV HD.
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    ForEach(Self.flyers(at: t)) { f in
                        // Långsamt i mitten, fortare mot kanten: som att bilderna flyger förbi en.
                        let r = pow(f.u, 2.2) * w * 0.95
                        let scale = 0.06 + pow(f.u, 1.9) * 1.5
                        Image(f.name).resizable().aspectRatio(16 / 9, contentMode: .fit)
                            .frame(width: w * 0.42)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                            .scaleEffect(scale)
                            .rotationEffect(.degrees(f.tilt * f.u))
                            .opacity(min(max((f.u - 0.12) / 0.25, 0), 1))
                            .position(x: w / 2 + cos(f.angle) * r, y: h / 2 + sin(f.angle) * r * 0.75)
                    }
                }
            }
            // Mörkare i mitten, så att texten går att läsa mot de brokiga bilderna.
            RadialGradient(colors: [Color(red: 0.08, green: 0.05, blue: 0.25).opacity(0.92), Color(red: 0.08, green: 0.05, blue: 0.25).opacity(0)],
                           center: .center, startRadius: 250, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}

/// Liten slumpgenerator med fast frö: samma bild flyger åt samma håll under hela sitt varv.
struct SplitMixTV {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func unit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}

/// Signaturmelodin i väntläget. Play/paus på fjärren stänger av och sätter på den, och valet sparas.
@MainActor @Observable
final class WaitingMusic {
    private var player: AVAudioPlayer?
    var muted = UserDefaults.standard.bool(forKey: "waitingMusicOff") {
        didSet { UserDefaults.standard.set(muted, forKey: "waitingMusicOff"); muted ? stop() : start() }
    }

    func start() {
        guard !muted, player == nil, let url = Bundle.main.url(forResource: "waiting", withExtension: "mp3"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        // "Ambient": bakgrundsmusik som inte tar över annat ljud.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        p.numberOfLoops = -1
        p.volume = 0
        p.play()
        p.setVolume(0.45, fadeDuration: 2)
        player = p
    }

    func stop() {
        guard let p = player else { return }
        player = nil
        p.setVolume(0, fadeDuration: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { p.stop() }
    }
}

/// Kortbunten ur ikonen. Korten vaggar lite, som om de väntar på att få börja.
struct LogoCards: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let sway = sin(t * 0.9)
            ZStack {
                card(Color(red: 1, green: 0.28, blue: 0.34)).rotationEffect(.degrees(15 + 4 * sway))
                card(Color(red: 0.12, green: 0.56, blue: 1)).rotationEffect(.degrees(2 * sin(t * 0.7)))
                card(Color(red: 1, green: 0.76, blue: 0.07))
                    .overlay { Text("W!").font(.system(size: 130, weight: .heavy, design: .rounded)).foregroundStyle(.white) }
                    .rotationEffect(.degrees(-15 - 4 * sway))
                    .offset(x: 26, y: 4 * sin(t * 1.3))
            }
            .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
        }
        .frame(width: 520, height: 360)
        .accessibilityHidden(true)
    }

    private func card(_ c: Color) -> some View {
        RoundedRectangle(cornerRadius: 28).fill(c).frame(width: 420, height: 240)
    }
}

/// Tre steg, så att även den som aldrig sett appen förstår vad man gör.
struct HowToSteps: View {
    private let steps: [(String, String)] = [
        ("iphone", "Öppna Woop Woop på telefonen eller iPaden"),
        ("rectangle.on.rectangle.angled", "Välj en presentation"),
        ("person.2.wave.2.fill", "Tryck Dela, så visas den här"),
    ]
    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            ForEach(steps.indices, id: \.self) { i in
                VStack(spacing: 18) {
                    ZStack(alignment: .topLeading) {
                        Image(systemName: steps[i].0).font(.system(size: 56, weight: .semibold))
                            .frame(width: 150, height: 150)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 32))
                        Text("\(i + 1)").font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.11, green: 0.08, blue: 0.39))
                            .frame(width: 52, height: 52).background(Color(red: 1, green: 0.76, blue: 0.07), in: Circle())
                            .offset(x: -16, y: -16)
                    }
                    Text(steps[i].1).font(.system(size: 30, weight: .semibold)).multilineTextAlignment(.center)
                        .frame(width: 360)
                }
            }
        }
        .foregroundStyle(.white)
    }
}
