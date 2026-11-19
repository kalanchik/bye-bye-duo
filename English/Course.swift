import Foundation

nonisolated struct CourseModule: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let theory: String
}

nonisolated struct CourseSection: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let theory: String
}

nonisolated struct Lesson: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case lesson, homework, story

        var title: String {
            switch self {
            case .lesson: "Урок"
            case .homework: "Домашняя работа"
            case .story: "История"
            }
        }
    }

    let id: String
    let title: String
    var kind: Kind
    let theory: String
    let estimatedMinutes: Int?
    let timeLimitMinutes: Int?
    var exercises: [Exercise]
    var passingPercent: Int?
    var story: StoryScript?
    var levelTest: String?
    var spacedReview: Bool?

    var isCheckpoint: Bool { passingPercent != nil }
    var titleForKind: String { isCheckpoint ? "Контрольная работа" : kind.title }
    var icon: String {
        if isCheckpoint { return "checkmark.seal" }
        if kind == .story { return "text.bubble" }
        return kind == .homework ? "pencil.and.list.clipboard" : "book"
    }

    func passed(_ attempt: Attempt) -> Bool {
        guard let passingPercent, !attempt.feedback.isEmpty else { return false }
        guard attempt.correctCount * 100 >= passingPercent * attempt.feedback.count else { return false }
        guard levelTest != nil else { return true }
        return levelEvidence(for: attempt).allSatisfy { $0.total >= 3 && $0.correct * 100 >= 60 * $0.total }
    }

    func levelEvidence(for attempt: Attempt) -> [PlacementResult.Score] {
        PlacementResult.Skill.allCases.map { skill in
            let ids = Set(exercises.filter { $0.topic == skill.rawValue }.map(\.id))
            let checked = attempt.feedback.filter { ids.contains($0.id) }
            return PlacementResult.Score(skill: skill, correct: checked.count(where: \.correct), total: checked.count)
        }
    }

    func completed(_ progress: Progress) -> Bool {
        isCheckpoint ? progress.attempts.contains(where: passed) : progress.finished
    }

    func status(for progress: Progress) -> String {
        if isCheckpoint {
            if completed(progress) { return "Сдана" }
            if progress.finished { return "Нужно пересдать" }
        }
        return progress.status
    }
}

nonisolated struct Exercise: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case gap, choice, correction, written, dialogue, wordOrder
        case translationTiles, translationChoice, translationCard, translationPairs

        var title: String {
            switch self {
            case .gap: "Заполни пропуск"
            case .choice: "Выбери ответ"
            case .correction: "Исправь ошибку"
            case .written: "Свободный ответ"
            case .dialogue: "Диалог"
            case .wordOrder: "Собери предложение"
            case .translationTiles: "Собери перевод"
            case .translationChoice, .translationCard: "Переведи слово"
            case .translationPairs: "Собери пары"
            }
        }

        var needsCodex: Bool { self == .written || self == .dialogue }
        var usesWordBank: Bool { self == .wordOrder || self == .translationTiles }
        var usesChoices: Bool { self == .choice || self == .translationChoice }
        var requiresTyping: Bool { needsCodex || self == .gap || self == .correction || self == .translationCard }
    }

    struct TranslationPair: Codable, Sendable {
        let russian: String
        let english: String
    }

    let id: String
    var kind: Kind
    let prompt: String
    let options: [String]?
    var acceptedAnswers: [String]?
    let explanation: String?
    let rubric: String?
    let topic: String?
    var speechText: String?
    var words: [String]?
    var pairs: [TranslationPair]?
    var vocabularyIDs: [String]?
    // Used only in the SQLite representation so older MCP processes can still list the course.
    var storedFormat: Kind?

    var title: String { speechText == nil ? kind.title : "Понимание на слух" }

    // Older lessons sometimes embedded the requested phrase in a teaching instruction.
    // Only extract it when the instruction identifies the target or the adjacent translation matches the key.
    var translationCardFront: String? {
        guard kind == .translationCard, let key = acceptedAnswers?.first, key.isShortCardTerm else { return nil }
        if prompt.isShortCardTerm { return prompt.trimmed }
        let quotedTargets = prompt.matches(of: /(?i)(?:переведи(?:те)?|напечатай(?:те)?|спроси(?:те)?)[^«»".!?\n]{0,64}[«"]([^«»"\n]+)[»"]/)
        if quotedTargets.count == 1, let match = quotedTargets.first {
            let term = String(match.1).trimmed
            if term.isShortCardTerm { return term }
        }
        let translations = prompt.matches(of: /(?:^|[:;\n])\s*([^:;\n—]+?)\s+—\s+([^.!?;\n]+)/)
        let matching = translations.compactMap { match -> String? in
            guard String(match.1).normalizedAnswer == key.normalizedAnswer else { return nil }
            let term = String(match.2).trimmed
            return term.isShortCardTerm ? term : nil
        }
        return Set(matching).count == 1 ? matching.first : nil
    }

    func grade(_ answer: String) -> Feedback {
        let accepted = kind == .translationPairs ? [pairAnswer] : acceptedAnswers ?? []
        let isCorrect = accepted.contains { $0.normalizedAnswer == answer.normalizedAnswer }
        return Feedback(
            id: id,
            correct: isCorrect,
            explanation: explanation ?? "",
            suggestion: isCorrect ? "" : (accepted.first ?? ""),
            source: .local
        )
    }

    var pairAnswer: String {
        (pairs ?? []).map { "\($0.russian) — \($0.english)" }.joined(separator: "\n")
    }

    func canBuildTranslation(_ answer: String) -> Bool {
        guard let words, words.count <= 16 else { return false }
        let target = answer.normalizedAnswer
        var failed = Set<Int>()
        func build(prefix: String, used: Int) -> Bool {
            if failed.contains(used) { return false }
            for index in words.indices where used & (1 << index) == 0 {
                let phrase = prefix + words[index].normalizedSpacing
                if phrase.normalizedAnswer == target { return true }
                if target.hasPrefix(phrase + " "), build(prefix: phrase + " ", used: used | (1 << index)) { return true }
            }
            failed.insert(used)
            return false
        }
        return build(prefix: "", used: 0)
    }
}

nonisolated struct CourseEntry: Codable, Sendable {
    let module: CourseModule
    let section: CourseSection
    let lesson: Lesson

    func validate() throws {
        let identifiers = [module.id, section.id, lesson.id] + lesson.exercises.map(\.id)
        guard identifiers.allSatisfy({ $0.range(of: #"^[a-z0-9][a-z0-9-]{0,79}$"#, options: .regularExpression) != nil }),
              Set(lesson.exercises.map(\.id)).count == lesson.exercises.count else {
            throw CourseError.invalid("Используй уникальные идентификаторы упражнений и короткие ID из латинских букв, цифр и дефисов.")
        }
        guard [module.title, section.title, lesson.title].allSatisfy({ !$0.trimmed.isEmpty }),
              (1...30).contains(lesson.exercises.count),
              [lesson.estimatedMinutes, lesson.timeLimitMinutes].compactMap({ $0 }).allSatisfy({ (1...240).contains($0) }) else {
            throw CourseError.invalid("Нужны названия модуля, раздела и урока, от 1 до 30 упражнений и время от 1 до 240 минут.")
        }
        for exercise in lesson.exercises {
            guard !exercise.prompt.trimmed.isEmpty else {
                throw CourseError.invalid("Добавь условие к упражнению \(exercise.id).")
            }
            if exercise.vocabularyIDs != nil {
                throw CourseError.invalid("Связь со словарём назначается при открытии урока.")
            }
            if exercise.storedFormat != nil {
                throw CourseError.invalid("Формат задания задаётся в поле kind.")
            }
            if exercise.words != nil, !exercise.kind.usesWordBank {
                throw CourseError.invalid("Слова для сборки доступны только в задании на порядок слов.")
            }
            if exercise.pairs != nil, exercise.kind != .translationPairs {
                throw CourseError.invalid("Поле pairs доступно только в задании на пары.")
            }
            if let text = exercise.speechText,
               exercise.kind != .choice || text.trimmed.isEmpty || text.count > 2_000 {
                throw CourseError.invalid("Для аудирования \(exercise.id) нужны варианты ответа и короткий текст для озвучивания.")
            }
            if exercise.kind.needsCodex { continue }
            if exercise.kind == .translationPairs {
                let pairs = exercise.pairs ?? []
                let sides = [pairs.map(\.russian), pairs.map(\.english)]
                guard (2...8).contains(pairs.count), sides.allSatisfy({ side in
                    Set(side.map(\.normalizedAnswer)).count == side.count && side.allSatisfy {
                        !$0.normalizedAnswer.isEmpty && $0.rangeOfCharacter(from: .newlines) == nil
                    }
                }), exercise.explanation?.trimmed.isEmpty == false else {
                    throw CourseError.invalid("Для \(exercise.id) нужны 2–8 однозначных пар и объяснение.")
                }
                continue
            }
            let accepted = exercise.acceptedAnswers ?? []
            guard !accepted.isEmpty, accepted.allSatisfy({ !$0.normalizedAnswer.isEmpty }),
                  let explanation = exercise.explanation, !explanation.trimmed.isEmpty else {
                throw CourseError.invalid("Добавь ключ и объяснение к упражнению \(exercise.id).")
            }
            if exercise.kind == .translationCard,
               !exercise.prompt.isShortCardTerm || !accepted.allSatisfy(\.isShortCardTerm) {
                throw CourseError.invalid("В карточке \(exercise.id) оставь только слово или короткую фразу и её перевод. Пояснение помести в explanation.")
            }
            if exercise.kind.usesChoices {
                let options = exercise.options ?? []
                let normalized = Set(options.map(\.normalizedAnswer))
                guard options.count >= 2, options.count == normalized.count, !normalized.contains(""),
                      accepted.allSatisfy({ normalized.contains($0.normalizedAnswer) }),
                      normalized.count > Set(accepted.map(\.normalizedAnswer)).count else {
                    throw CourseError.invalid("Для \(exercise.id) нужны разные варианты, среди которых есть правильный и неправильный.")
                }
            }
            if exercise.kind == .wordOrder {
                let words = exercise.words ?? []
                guard (2...16).contains(words.count), words.allSatisfy({ !$0.normalizedAnswer.isEmpty }),
                      accepted.allSatisfy({
                          $0.normalizedAnswer.split(separator: " ").map(String.init).sorted()
                              == words.joined(separator: " ").normalizedAnswer.split(separator: " ").map(String.init).sorted()
                      }) else { throw CourseError.invalid("Проверь слова и допустимые фразы в задании \(exercise.id).") }
            }
            if exercise.kind == .translationTiles {
                guard let words = exercise.words, (2...16).contains(words.count),
                      words.allSatisfy({ !$0.normalizedAnswer.isEmpty }),
                      accepted.allSatisfy(exercise.canBuildTranslation) else {
                    throw CourseError.invalid("Каждый перевод в \(exercise.id) должен собираться из предложенных слов.")
                }
            }
        }
        if lesson.kind == .story {
            guard let story = lesson.story else { throw CourseError.invalid("Добавь сцены истории.") }
            try story.validate(exercises: lesson.exercises)
        } else if lesson.story != nil {
            throw CourseError.invalid("Сцены доступны только для истории.")
        }
        if let percent = lesson.passingPercent, !(1...100).contains(percent) {
            throw CourseError.invalid("Проходной балл контрольной должен быть от 1 до 100 процентов.")
        }
        if lesson.levelTest != nil {
            guard lesson.isCheckpoint, PlacementResult.Skill.allCases.allSatisfy({ skill in
                lesson.exercises.filter { $0.topic == skill.rawValue }.count >= 3
            }) else { throw CourseError.invalid("В проверке уровня нужно не меньше трёх заданий по каждому навыку.") }
        }
    }
}

nonisolated struct Feedback: Codable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable { case local, codex }

    let id: String
    let correct: Bool
    let explanation: String
    let suggestion: String
    let source: Source
}

nonisolated struct Attempt: Codable, Identifiable, Sendable {
    var id = UUID()
    var date = Date()
    let answers: [String: String]
    let feedback: [Feedback]
    var checks: [ExerciseCheck]?
    var celebration: LessonCelebration?
    var studySeconds: TimeInterval?
    var vocabularyCards: [VocabularyCard]?

    var correctCount: Int { feedback.count(where: \.correct) }
}

nonisolated struct Progress: Codable, Sendable {
    var draft: [String: String] = [:]
    var attempts: [Attempt] = []
    var isRetrying = false
    var timerEndsAt: Date?
    var dueAt: Date?
    var reminderAt: Date?
    var practice: PracticeDraft?
    var vocabularyCards: [VocabularyCard]?

    var finished: Bool { !attempts.isEmpty && !isRetrying }

    var status: String {
        if finished { return "Выполнено" }
        if isRetrying || timerEndsAt != nil || practice != nil || draft.values.contains(where: { !$0.trimmed.isEmpty }) { return "В процессе" }
        return "К выполнению"
    }
}

nonisolated struct CourseSnapshot: Sendable {
    var entries: [CourseEntry] = []
    var progress: [String: Progress] = [:]
    var vocabulary: [String: [VocabularyItem]] = [:]
    var agentUsage: [AgentUsage] = []
    var extraVocabularyChecks: [Date: Int] = [:]
    var vocabularyPracticeDays: Set<Date> = []

    var firstChecks: [ExerciseCheck] {
        progress.sorted { $0.key < $1.key }.flatMap { _, progress in
            if let attempt = progress.attempts.first {
                return attempt.checks ?? attempt.feedback.map { ExerciseCheck(feedback: $0, date: attempt.date) }
            }
            return progress.practice?.checks ?? []
        }
        .sorted { $0.date < $1.date }
    }

    var correctAnswerStreak: Int { firstChecks.reversed().prefix(while: { $0.feedback.correct }).count }

    func practiceDays(calendar: Calendar = .current) -> Set<Date> {
        var days = vocabularyPracticeDays
        for progress in progress.values {
            for check in progress.practice?.checks ?? [] {
                days.insert(calendar.startOfDay(for: check.date))
            }
            for attempt in progress.attempts where !attempt.feedback.isEmpty {
                for date in attempt.checks?.map(\.date) ?? [attempt.date] {
                    days.insert(calendar.startOfDay(for: date))
                }
            }
        }
        return days
    }

    func practiceDayStreak(at now: Date, calendar: Calendar = .current) -> Int {
        let days = practiceDays(calendar: calendar)
        let today = calendar.startOfDay(for: now)
        var count = 0
        var date = today
        if !days.contains(today), let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            date = yesterday
        }
        while days.contains(date) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = calendar.startOfDay(for: previous)
        }
        return count
    }

    var sections: [StudySection] {
        var positions: [String: Int] = [:]
        var sections: [StudySection] = []
        for entry in entries {
            let id = "\(entry.module.id)/\(entry.section.id)"
            if let position = positions[id] {
                sections[position].entries.append(entry)
            } else {
                positions[id] = sections.count
                sections.append(StudySection(id: id, entries: [entry]))
            }
        }
        return sections
    }
}

nonisolated struct StudySection: Identifiable, Sendable {
    let id: String
    var entries: [CourseEntry]

    var orderedEntries: [CourseEntry] {
        let practice = entries.filter { !$0.lesson.isCheckpoint }
        let introductoryIDs = ["simple-from-zero", "continuous-actions-now"]
        return practice.filter { introductoryIDs.contains($0.lesson.id) }
            + practice.filter { !introductoryIDs.contains($0.lesson.id) }
            + entries.filter(\.lesson.isCheckpoint)
    }

    func completed(_ progress: [String: Progress]) -> Bool {
        let checkpoints = entries.filter(\.lesson.isCheckpoint)
        let required = checkpoints.isEmpty ? entries : checkpoints
        return !required.isEmpty && required.allSatisfy {
            $0.lesson.completed(progress[$0.lesson.id] ?? Progress())
        }
    }
}

nonisolated enum CourseError: LocalizedError {
    case invalid(String)
    case storage(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(message), let .storage(message): message
        }
    }
}

extension String {
    nonisolated var isShortCardTerm: Bool {
        let term = trimmed
        return !term.isEmpty && term.count <= 64 && term.split(whereSeparator: \.isWhitespace).count <= 6
            && term.rangeOfCharacter(from: .newlines) == nil
            && term.range(of: #"[():;«»"—]|\s[-–]\s"#, options: .regularExpression) == nil
            && term.range(of: #"^(?:переведи(?:те)?|напечатай(?:те)?|переведи\s+на|translate|type the translation)\s"#,
                          options: [.regularExpression, .caseInsensitive]) == nil
    }

    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    nonisolated var normalizedAnswer: String {
        normalizedSpacing.trimmingCharacters(in: CharacterSet(charactersIn: ".!?")).trimmed
    }

    nonisolated var normalizedSpacing: String {
        replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

nonisolated struct StudyRun {
    var id = UUID()
    let lessonID: String
    let start: Date
    var activityID: String?

    var key: String { activityID ?? lessonID }

    func interval(through end: Date) -> StudyInterval {
        StudyInterval(id: id, lessonID: lessonID, start: start, end: end)
    }
}

nonisolated struct VocabularyCard: Codable, Identifiable, Sendable {
    let id: String
    let english: String
    let russian: String
    let example: String
    let exampleTranslation: String
    var acceptedAnswers: [String]?

    func accepts(_ answer: String) -> Bool {
        let normalized = answer.normalizedAnswer
        return ([english] + (acceptedAnswers ?? [])).contains { $0.normalizedAnswer == normalized }
    }
    func validate() throws {
        guard id.range(of: #"^[a-z0-9][a-z0-9-]{0,79}$"#, options: .regularExpression) != nil,
              [english, russian, example, exampleTranslation].allSatisfy({ !$0.trimmed.isEmpty && $0.count <= 300 }),
              (acceptedAnswers ?? []).allSatisfy({ !$0.normalizedAnswer.isEmpty && $0.count <= 300 }),
              !english.normalizedAnswer.isEmpty, !russian.normalizedAnswer.isEmpty else {
            throw CourseError.invalid("Карточке \(id) нужны слово, перевод, пример и перевод примера.")
        }
        guard english.isShortCardTerm, russian.isShortCardTerm else {
            throw CourseError.invalid("На каждой стороне карточки \(id) оставь слово или короткую фразу. Пример запиши в example и exampleTranslation.")
        }
    }
}

nonisolated struct VocabularyReview: Codable, Sendable {
    let level: Int
    let dueAt: Date

    static func next(after previous: VocabularyReview?, correct: Bool, now: Date) -> Self {
        guard correct else { return Self(level: 0, dueAt: now.addingTimeInterval(10 * 60)) }
        let days = [1, 3, 7, 14, 30]
        let level = min(max(0, previous?.level ?? 0), days.count - 1) + 1
        let due = Calendar.current.date(byAdding: .day, value: days[level - 1], to: now) ?? now
        return Self(level: level, dueAt: due)
    }
}

nonisolated struct VocabularyItem: Identifiable, Sendable {
    let card: VocabularyCard
    var review: VocabularyReview?

    var id: String { card.id }

    func isDue(at now: Date) -> Bool { review.map { $0.dueAt <= now } ?? true }
}

nonisolated struct StudyInterval {
    let id: UUID
    let lessonID: String
    let start: Date
    let end: Date
}
