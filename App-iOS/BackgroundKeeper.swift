import AVFoundation

/// Håller appen vaken i bakgrunden medan man delar eller är med i en delning.
///
/// iOS pausar annars appen efter cirka 30 sekunder, och då tappar TV:n och de andra kontakten.
/// Det händer hela tiden: man går till Safari för att kopiera en bild, eller öppnar fjärren.
/// En app som spelar ljud får fortsätta köra, så vi spelar tystnad (blandad med annat ljud,
/// så att musik och annat inte störs). Efter en kvart ger vi upp för batteriets skull.
@MainActor
final class BackgroundKeeper {
    static let limit: TimeInterval = 15 * 60
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    /// Sant om appen fick köra hela tiden i bakgrunden (ljudet spelar fortfarande).
    var isRunning: Bool { player?.isPlaying == true }

    func start() {
        guard player == nil else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
        guard let p = try? AVAudioPlayer(data: Self.silence) else { return }
        p.numberOfLoops = -1
        p.volume = 0
        p.play()
        player = p
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.limit * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel(); stopTask = nil
        player?.stop(); player = nil
    }

    /// En sekund tystnad som WAV (8 kHz, 16 bitar, mono).
    private static let silence: Data = {
        let n = 8000
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(Data("RIFF".utf8)); u32(UInt32(36 + n * 2)); d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); u32(16); u16(1); u16(1); u32(8000); u32(16000); u16(2); u16(16)
        d.append(Data("data".utf8)); u32(UInt32(n * 2))
        d.append(Data(count: n * 2))
        return d
    }()
}
