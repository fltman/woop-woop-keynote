import Foundation

/// Ljudknapparna i presentationen. Ljuden är inspelade effekter (gjorda med ElevenLabs) som följer
/// med appen, så de finns på alla enheter utan att skickas över nätet. Saknas en fil används
/// ett enklare ljud som räknas fram i koden.
public enum Jingle: String, Codable, CaseIterable, Sendable {
    case woop, drumroll, tada, applause, trombone, boing, fart

    public var name: String {
        switch self {
        case .woop: "Woop woop"
        case .drumroll: "Trumvirvel"
        case .tada: "Ta-daa"
        case .applause: "Applåder"
        case .trombone: "Ledsen trombon"
        case .boing: "Boing"
        case .fart: "Pruttkudde"
        }
    }

    public var emoji: String {
        switch self {
        case .woop: "🎉"
        case .drumroll: "🥁"
        case .tada: "✨"
        case .applause: "👏"
        case .trombone: "📉"
        case .boing: "🌀"
        case .fart: "💨"
        }
    }

    /// Ljudet som ska spelas: den medföljande filen (mp3), annars det framräknade (wav).
    public func data() -> Data {
        if let u = Bundle.module.url(forResource: rawValue, withExtension: "mp3", subdirectory: "Jingles"),
           let d = try? Data(contentsOf: u) { return d }
        return wav()
    }

    static let rate = 22050.0

    /// Ljudet som mono-samplingar i −1…1.
    func samples() -> [Float] {
        var rng = SplitMix(seed: 7)
        func noise() -> Double { Double(rng.next() >> 11) / Double(1 << 53) * 2 - 1 }
        let sr = Self.rate
        func buffer(_ seconds: Double) -> [Double] { [Double](repeating: 0, count: Int(seconds * sr)) }
        var out: [Double]

        switch self {
        case .woop:
            // Två glada svep uppåt.
            out = buffer(0.75)
            for (k, start) in [0.0, 0.38].enumerated() {
                var phase = 0.0
                let len = 0.3
                for i in 0..<Int(len * sr) {
                    let t = Double(i) / sr, u = t / len
                    let f = (k == 0 ? 320.0 : 380.0) * pow(3.0, u)
                    phase += 2 * .pi * f / sr
                    let env = sin(.pi * min(u * 1.15, 1)) * (1 - u * 0.3)
                    out[Int(start * sr) + i] += (sin(phase) + 0.35 * sin(2 * phase) + 0.15 * sin(3 * phase)) * env * 0.6
                }
            }
        case .drumroll:
            // Täta virvelslag som växer, och en smäll på slutet.
            out = buffer(2.3)
            var t = 0.0
            while t < 1.75 {
                let gain = 0.18 + 0.5 * (t / 1.75)
                hit(&out, at: t, length: 0.05, gain: gain * (0.8 + 0.2 * noise()), tone: 190, noise: noise)
                t += 0.034 + 0.004 * noise()
            }
            hit(&out, at: 1.82, length: 0.45, gain: 1.0, tone: 120, noise: noise)
        case .tada:
            out = buffer(1.5)
            chord(&out, at: 0, length: 0.16, notes: [523.25, 659.25, 783.99], gain: 0.22)
            chord(&out, at: 0.2, length: 1.25, notes: [523.25, 659.25, 783.99, 1046.5], gain: 0.2)
        case .applause:
            // Hundratals små klappar: korta brusstötar med lite olika klang.
            out = buffer(3.0)
            for _ in 0..<520 {
                let at = (noise() + 1) / 2 * 2.8
                let env = min(at / 0.3, 1) * min((2.9 - at) / 1.2, 1)
                clap(&out, at: at, gain: (0.12 + 0.1 * (noise() + 1) / 2) * env, colour: 0.25 + 0.5 * (noise() + 1) / 2, noise: noise)
            }
        case .trombone:
            // Wah, wah, wah, waaaah.
            out = buffer(2.3)
            let notes: [(f: Double, at: Double, len: Double)] = [(233.08, 0, 0.36), (220, 0.4, 0.36), (207.65, 0.8, 0.36), (196, 1.2, 1.0)]
            for (n, note) in notes.enumerated() {
                var phase = 0.0, lp = 0.0
                for i in 0..<Int(note.len * sr) {
                    let t = Double(i) / sr, u = t / note.len
                    var f = note.f
                    if n == 3 { f *= 1 - 0.1 * u * u; f *= 1 + 0.012 * sin(2 * .pi * 5.5 * t) * u }
                    phase += f / sr
                    let saw = 2 * (phase - floor(phase + 0.5))
                    // "Wah": lågpassfiltret öppnar sig i början av varje ton.
                    let a = 0.04 + 0.2 * min(u * 4, 1) * (1 - 0.6 * u)
                    lp += a * (saw - lp)
                    let env = min(t / 0.03, 1) * min((note.len - t) / 0.08, 1)
                    out[Int(note.at * sr) + i] += lp * env * 0.9
                }
            }
        case .fart:
            // Reserv om filen saknas: ett lågt, fladdrigt surr som sjunker.
            out = buffer(0.9)
            var phase = 0.0
            for i in 0..<out.count {
                let t = Double(i) / sr
                let f = 95 - 30 * t + 12 * sin(2 * .pi * 9 * t) + 6 * noise()
                phase += f / sr
                let pulse = (phase - floor(phase)) < 0.35 ? 1.0 : -0.4
                out[i] = pulse * min(t / 0.02, 1) * min((0.9 - t) / 0.15, 1) * (0.7 + 0.3 * noise())
            }
        case .boing:
            out = buffer(0.8)
            var phase = 0.0
            for i in 0..<out.count {
                let t = Double(i) / sr
                let f = 150 + 260 * exp(-t * 3) * (1 + 0.5 * sin(2 * .pi * 11 * t))
                phase += 2 * .pi * f / sr
                out[i] = (sin(phase) + 0.3 * sin(2 * phase)) * exp(-t * 4.5) * 0.7
            }
        }
        let peak = max(out.map { abs($0) }.max() ?? 1, 0.001)
        let k = min(0.9 / peak, 4)
        return out.map { Float($0 * k) }
    }

    private func hit(_ out: inout [Double], at: Double, length: Double, gain: Double, tone: Double, noise: () -> Double) {
        let sr = Self.rate, start = Int(at * sr)
        for i in 0..<Int(length * sr) where start + i < out.count {
            let t = Double(i) / sr
            out[start + i] += (noise() * exp(-t * 60 / (length * 20)) + 0.6 * sin(2 * .pi * tone * t) * exp(-t * 30)) * gain
        }
    }

    private func clap(_ out: inout [Double], at: Double, gain: Double, colour: Double, noise: () -> Double) {
        let sr = Self.rate, start = Int(at * sr)
        var lp = 0.0
        for i in 0..<Int(0.03 * sr) where start + i < out.count {
            let t = Double(i) / sr
            let n = noise()
            lp += colour * (n - lp)
            out[start + i] += (n - lp) * exp(-t * 220) * gain   // högpass: klappar är ljusa
        }
    }

    private func chord(_ out: inout [Double], at: Double, length: Double, notes: [Double], gain: Double) {
        let sr = Self.rate, start = Int(at * sr)
        for i in 0..<Int(length * sr) where start + i < out.count {
            let t = Double(i) / sr
            let env = min(t / 0.01, 1) * exp(-t * 2.2) * min((length - t) / 0.05, 1)
            var v = 0.0
            for f in notes { for h in 1...4 { v += sin(2 * .pi * f * Double(h) * t) / Double(h * h) } }
            out[start + i] += v * env * gain
        }
    }

    /// Färdig WAV-fil (16 bitar, mono).
    public func wav() -> Data {
        let s = samples()
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(s.count * 2), sr = UInt32(Self.rate)
        d.append("RIFF".data(using: .ascii)!); u32(36 + bytes); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(sr); u32(sr * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(bytes)
        d.reserveCapacity(44 + s.count * 2)
        for v in s { u16(UInt16(bitPattern: Int16(max(-1, min(1, v)) * 32767))) }
        return d
    }
}

/// Liten slumpgenerator med fast frö, så att ljuden låter likadant varje gång.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
