import Foundation

nonisolated struct StoryScript: Codable, Sendable {
    struct Scene: Codable, Identifiable, Sendable {
        struct Line: Codable, Identifiable, Sendable {
            let id: String
            let speaker: String?
            let text: String
        }

        let id: String
        let lines: [Line]
        let exercises: [String]
        var title: String?
        var instruction: String?
    }

    let version: Int
    let scenes: [Scene]

    func validate(exercises: [Exercise]) throws {
        let lines = scenes.flatMap(\.lines)
        let ids = scenes.map(\.id) + lines.map(\.id)
        let speakers = Set(lines.compactMap(\.speaker))
        guard version > 0, !scenes.isEmpty, scenes.count <= 12,
              scenes.allSatisfy({ !$0.lines.isEmpty && $0.lines.count <= 12 }),
              ids.allSatisfy({ $0.range(of: #"^[a-z0-9][a-z0-9-]{0,79}$"#, options: .regularExpression) != nil }),
              Set(ids).count == ids.count,
              lines.allSatisfy({ !$0.text.trimmed.isEmpty && $0.text.count <= 1_000 }),
              speakers.count <= 3, speakers.allSatisfy({ !$0.trimmed.isEmpty && $0.count <= 40 }),
              scenes.flatMap(\.exercises) == exercises.map(\.id) else {
            throw CourseError.invalid("Проверь ID и порядок сцен, реплик и заданий. В истории может быть до трёх персонажей.")
        }
    }
}

nonisolated struct ExerciseCheck: Codable, Sendable {
    let feedback: Feedback
    let date: Date
    var reachedMilestone: Bool?
}

nonisolated enum LessonCelebration: String, Codable, Sendable {
    case completed, perfect, streak, story, checkpointFailed
}

nonisolated struct PracticeDraft: Codable, Sendable {
    var stepID: String
    var checks: [ExerciseCheck] = []
    var startedAt = Date.now
    var wordTiles: [String: [Int]] = [:]
    var pairSelections: [String: TranslationPairSelection]?
    var storyVersion: Int?
}

nonisolated struct TranslationPairSelection: Codable, Sendable {
    struct Pick: Codable, Equatable, Sendable {
        let index: Int
        let side: Side
        enum Side: String, Codable, Sendable { case russian, english }
    }

    var pending: Pick?
    private(set) var links: [Int: Int] = [:]

    func partner(of pick: Pick) -> Int? {
        switch pick.side {
        case .russian: links[pick.index]
        case .english: links.first { $0.value == pick.index }?.key
        }
    }

    mutating func select(_ pick: Pick) {
        if let partner = partner(of: pick) {
            links.removeValue(forKey: pick.side == .russian ? pick.index : partner)
            pending = pick
        } else if let first = pending, first.side != pick.side {
            let russian = pick.side == .russian ? pick : first
            let english = pick.side == .english ? pick : first
            links[russian.index] = english.index
            pending = nil
        } else {
            pending = pending == pick ? nil : pick
        }
    }

    func answer(for pairs: [Exercise.TranslationPair]) -> String {
        guard !pairs.isEmpty, links.count == pairs.count else { return "" }
        var lines = [String]()
        for index in pairs.indices {
            guard let other = links[index], pairs.indices.contains(other) else { return "" }
            lines.append("\(pairs[index].russian) — \(pairs[other].english)")
        }
        return lines.joined(separator: "\n")
    }
}

extension Progress {
    nonisolated func canSubmit(_ exercise: Exercise) -> Bool {
        guard draft[exercise.id]?.trimmed.isEmpty == false else { return false }
        if exercise.kind == .wordOrder {
            return practice?.wordTiles[exercise.id]?.count == exercise.words?.count
        }
        return true
    }
}

nonisolated enum PracticeStep: Identifiable {
    case line(StoryScript.Scene.Line, part: Int)
    case exercise(Exercise, number: Int)

    var id: String {
        switch self {
        case .line(let line, _): "line/\(line.id)"
        case .exercise(let exercise, _): "exercise/\(exercise.id)"
        }
    }
}

extension Lesson {
    nonisolated var practiceSteps: [PracticeStep] {
        let questions = exercises.enumerated().map { PracticeStep.exercise($0.element, number: $0.offset + 1) }
        guard let story else { return questions }
        let byID = Dictionary(uniqueKeysWithValues: zip(exercises.map(\.id), questions))
        return story.scenes.enumerated().flatMap { index, scene in
            scene.lines.map { PracticeStep.line($0, part: index + 1) } + scene.exercises.compactMap { byID[$0] }
        }
    }
}
