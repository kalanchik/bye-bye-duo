import CryptoKit
import Foundation

// Save the chosen cards with the draft and attempt so that their prompts, keys and order survive a restart.
extension Lesson {
    nonisolated func includingVocabulary(_ cards: [VocabularyCard]) -> Lesson {
        guard !isCheckpoint, story == nil, !cards.isEmpty else { return self }
        var lesson = self
        var additions: [Exercise] = []
        var ids = Set(exercises.map(\.id))
        func exerciseID(for cards: [VocabularyCard]) -> String {
            let key = cards.map(\.id).joined(separator: "|")
            let digest = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
            let base = "vocab-\(digest)"
            var id = base
            var suffix = 0
            while !ids.insert(id).inserted {
                suffix += 1
                id = "\(base)-\(suffix)"
            }
            return id
        }

        // A small matching exercise introduces words before the independent translations.
        let space = 30 - exercises.count
        guard space > 0 else { return self }
        let pairCount = cards.count >= 3 && space > 1 ? min(4, cards.count - 1) : 0
        if pairCount > 0 {
            let group = Array(cards.prefix(pairCount))
            let pairs = group.map { Exercise.TranslationPair(russian: $0.russian, english: $0.english) }
            additions.append(Exercise(id: exerciseID(for: group), kind: .translationPairs, prompt: "Соедини слова с переводом",
                                      options: nil, acceptedAnswers: nil,
                                      explanation: group.map { "\($0.example) — \($0.exampleTranslation)" }.joined(separator: "\n\n"),
                                      rubric: nil, topic: "Слова раздела", pairs: pairs,
                                      vocabularyIDs: group.map(\.id)))
        }
        for card in cards.dropFirst(pairCount).prefix(space - additions.count) {
            additions.append(Exercise(id: exerciseID(for: [card]), kind: .translationCard, prompt: card.russian,
                                      options: nil, acceptedAnswers: [card.english] + (card.acceptedAnswers ?? []),
                                      explanation: "\(card.example) — \(card.exampleTranslation)",
                                      rubric: nil, topic: "Слова раздела", vocabularyIDs: [card.id]))
        }
        // Keep the opening example and distribute vocabulary through the rest of the lesson.
        for (index, exercise) in additions.enumerated().reversed() {
            let position = max(1, exercises.count * (index + 1) / (additions.count + 1))
            lesson.exercises.insert(exercise, at: min(position, exercises.count))
        }
        return lesson
    }
}

func vocabularyRoundCards(
    _ items: [VocabularyItem], previous: [VocabularyCard], retry: Set<String>
) -> [VocabularyCard] {
    let now = Date.now
    let due = items.filter { $0.isDue(at: now) || retry.contains($0.id) }
    let previousIDs = Set(previous.map(\.id))
    let otherCards = items.filter { !previousIDs.contains($0.id) }
    let candidates = due.isEmpty ? (otherCards.isEmpty ? items : otherCards) : due
    let ordered = candidates.filter { retry.contains($0.id) } + candidates.filter { !retry.contains($0.id) }
    var cards: [VocabularyCard] = []
    var english = Set<String>()
    var russian = Set<String>()
    for item in ordered {
        let card = item.card
        let en = card.english.normalizedAnswer
        let ru = card.russian.normalizedAnswer
        guard !english.contains(en), !russian.contains(ru) else { continue }
        cards.append(card)
        english.insert(en)
        russian.insert(ru)
        if cards.count == 5 { break }
    }
    return cards
}
