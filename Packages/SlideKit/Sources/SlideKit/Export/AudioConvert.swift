import Foundation
import AVFoundation

/// Klickljud i .pptx (`<a:snd>`) måste vara WAV. Inspelningar är .m4a (AAC) och görs om till
/// 16-bitars PCM med AVAudioFile, som finns på macOS, iOS och tvOS.
enum AudioConvert {
    static func wav(_ data: Data, ext: String) -> Data? {
        if ext.lowercased() == "wav" { return data }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("woop-audio-\(UUID().uuidString)")
        let src = base.appendingPathExtension(ext)
        let dst = base.appendingPathExtension("wav")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        do {
            try data.write(to: src)
            try transcode(from: src, to: dst)
            return try Data(contentsOf: dst)
        } catch {
            return nil
        }
    }

    /// Egen funktion så att utfilen stängs (AVAudioFile släpps) innan den läses.
    private static func transcode(from src: URL, to dst: URL) throws {
        let input = try AVAudioFile(forReading: src)
        let fmt = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: fmt.sampleRate,
            AVNumberOfChannelsKey: fmt.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = try AVAudioFile(forWriting: dst, settings: settings,
                                     commonFormat: fmt.commonFormat, interleaved: fmt.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 16384) else { throw AssetError.unreadable }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
    }
}
