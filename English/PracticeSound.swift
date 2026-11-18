import AVFAudio
import OSLog

@MainActor
enum PracticeSound: String {
    case exerciseCorrect = "exercise-correct"
    case exerciseIncorrect = "exercise-incorrect"
    case pairCorrect = "pair-correct"
    case pairIncorrect = "pair-incorrect"
    case wordPick = "word-pick"
    case wordReturn = "word-return"
    case cardCorrect = "card-correct"

    private static var players: [Self: AVAudioPlayer] = [:]
    private static var activePlayer: AVAudioPlayer?
    private static let logger = Logger(subsystem: "local.englishpractice.study", category: "PracticeSound")

    static func answer(correct: Bool, translationCard: Bool = false) -> Self {
        guard correct else { return .exerciseIncorrect }
        return translationCard ? .cardCorrect : .exerciseCorrect
    }

    func play() {
        let player: AVAudioPlayer
        if let cached = Self.players[self] {
            player = cached
        } else {
            guard let url = Bundle.main.url(forResource: rawValue, withExtension: "wav", subdirectory: "PracticeSounds") else {
                Self.logger.error("Missing sound: \(self.rawValue)")
                return
            }
            do {
                player = try AVAudioPlayer(contentsOf: url)
                Self.players[self] = player
            } catch {
                Self.logger.error("Could not load \(self.rawValue): \(error.localizedDescription)")
                return
            }
        }

        if Self.activePlayer?.isPlaying == true { Self.activePlayer?.stop() }
        player.currentTime = 0
        Self.activePlayer = player
        if !player.play() {
            Self.players.removeValue(forKey: self)
            Self.activePlayer = nil
            Self.logger.error("Could not play \(self.rawValue)")
        }
    }
}
