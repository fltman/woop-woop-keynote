import AVFoundation

/// Spelar ljud på presentationsskärmen. Ett ljud i taget: ett nytt tryck avbryter det förra.
@MainActor
public final class SoundPlayer {
    public static let shared = SoundPlayer()
    private var player: AVAudioPlayer?
    private var lastNonce: UUID?

    public func play(_ cue: SoundCue, assets: AssetStore) {
        guard cue.nonce != lastNonce else { return }
        lastNonce = cue.nonce
        #if os(iOS) || os(tvOS)
        // Spela även när ljudlöst-knappen är på: det här är en presentation.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: assets.url(cue.asset))
        player?.play()
    }

    /// Förhandslyssning i editorn.
    public func preview(_ asset: String, assets: AssetStore) {
        play(SoundCue(element: UUID(), asset: asset), assets: assets)
    }

    public func stop() { player?.stop() }

    private var jingles: [Jingle: Data] = [:]
    private var jinglePlayer: AVAudioPlayer?
    private var lastJingle: UUID?

    /// Ljudknapparna. Spelas ovanpå elementljuden.
    public func play(_ j: Jingle, nonce: UUID) {
        guard nonce != lastJingle else { return }
        lastJingle = nonce
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let data = jingles[j] ?? j.data()
        jingles[j] = data
        jinglePlayer = try? AVAudioPlayer(data: data)
        jinglePlayer?.play()
    }
}
