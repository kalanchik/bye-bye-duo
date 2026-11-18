import AVFAudio
import Foundation
import Observation
import OSLog

enum PracticeVoice: String {
    case male = "M2"
    case female = "F2"

    static let preferenceKey = "practiceSpeechVoice"
    static let defaultVoice = Self.female

    static var selected: Self {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? defaultVoice
    }
}

@MainActor
@Observable
final class PracticeSpeech: NSObject, AVAudioPlayerDelegate {
    private enum Playback { case idle, playing, finished }
    private var playback = Playback.idle
    private static weak var active: PracticeSpeech?
    private static let logger = Logger(subsystem: "local.englishpractice.study", category: "PracticeSpeech")
    @ObservationIgnored private var synthesis: Process?
    @ObservationIgnored private var lastClip: (text: String, voice: PracticeVoice, player: AVAudioPlayer)?

    var isPlaying: Bool { playback == .playing }

    var playbackProgress: Double {
        switch playback {
        case .idle: return 0
        case .finished: return 1
        case .playing:
            guard let player = lastClip?.player, player.duration > 0 else { return 0 }
            return min(1, max(0, player.currentTime / player.duration))
        }
    }

    func play(_ text: String, voice: PracticeVoice = .selected, onError: @escaping @MainActor (String) -> Void) {
        Self.active?.stop()
        Self.active = self
        if let lastClip, lastClip.text == text, lastClip.voice == voice {
            start(lastClip.player, onError: onError)
            return
        }
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "voca"),
              let resources = Bundle.main.resourceURL else {
            onError("Не удалось найти движок озвучки tiny-voca в приложении.")
            return
        }

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        let process = Process()
        process.executableURL = executable
        process.environment = ["VOCA_HOME": resources.appendingPathComponent("TinyVoca").path]
        process.arguments = ["--voice", voice.rawValue, "--speed", "0.85", "--output", output.path, "--", text]
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                defer { try? FileManager.default.removeItem(at: output) }
                guard let self, self.synthesis === finished else { return }
                self.synthesis = nil
                guard finished.terminationStatus == 0 else {
                    onError("Не удалось озвучить английскую фразу.")
                    return
                }
                do {
                    let player = try AVAudioPlayer(data: Data(contentsOf: output))
                    self.lastClip = (text, voice, player)
                    self.start(player, onError: onError)
                } catch {
                    Self.logger.error("Cannot load synthesized audio: \(error.localizedDescription)")
                    onError("Не удалось прочитать аудиозапись.")
                }
            }
        }
        synthesis = process
        do {
            try process.run()
        } catch {
            synthesis = nil
            Self.logger.error("Cannot launch tiny-voca: \(error.localizedDescription)")
            onError("Не удалось запустить озвучку tiny-voca.")
        }
    }

    private func start(_ player: AVAudioPlayer, onError: (String) -> Void) {
        player.delegate = self
        player.currentTime = 0
        if player.play() {
            playback = .playing
        } else {
            onError("Не удалось воспроизвести звук.")
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard lastClip?.player === player, playback == .playing, !player.isPlaying else { return }
        playback = flag ? .finished : .idle
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        guard lastClip?.player === player else { return }
        stop()
    }

    func stop() {
        let process = synthesis
        synthesis = nil
        if let process, process.isRunning { process.terminate() }
        lastClip?.player.delegate = nil
        lastClip?.player.stop()
        playback = .idle
        if Self.active === self { Self.active = nil }
    }
}
