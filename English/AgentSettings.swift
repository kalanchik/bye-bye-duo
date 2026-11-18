import Foundation

nonisolated struct TutorModel: Decodable, Identifiable, Sendable {
    struct Effort: Decodable { let reasoningEffort: String }
    let model: String
    let displayName: String
    let defaultReasoningEffort: String
    let supportedReasoningEfforts: [Effort]
    let isDefault: Bool
    var id: String { model }
}

nonisolated struct TutorSelection: Codable, Sendable {
    let model: String
    let effort: String
}

nonisolated enum TutorPrompt: String, CaseIterable, Identifiable, Sendable {
    case section, checkpoint, levelTest, grading
    var id: Self { self }

    var title: String {
        switch self {
        case .section: "Уроки и практика раздела"
        case .checkpoint: "Контрольная по теме"
        case .levelTest: "Проверка уровня"
        case .grading: "Проверка ответов"
        }
    }

    var original: String {
        switch self {
        case .section:
            """
            Build a progression across {{lessonsPerSection}} teaching lessons, one homework assignment and one spaced review.
            Teach everyday English through concrete situations. Explain new vocabulary in context.
            In teaching lessons and homework, guide the first 4–6 exercises with examples, then gradually remove hints.
            Use fresh situations for homework. For spaced review, revisit the material after a pause.
            Each full step has {{exercisesPerLesson}} exercises. The review has {{reviewExercises}}.
            Include {{cardsPerSection}} distinct vocabulary cards across the section.
            """
        case .checkpoint:
            """
            Assess the studied topic in {{testExercises}} exercises using fresh everyday situations without hints.
            Include listening, reading and independent writing. Cover the material already studied.
            """
        case .levelTest:
            """
            Assess the learner's current level in {{testExercises}} exercises without hints.
            Use new situations. Include at least three items for each of grammar, reading, listening and writing.
            """
        case .grading:
            """
            Accept natural alternative answers that meet the rubric. Mark an answer correct if it fulfils
            the task without significant language errors. Distinguish errors from optional style improvements.
            Briefly explain the result in Russian. Give a corrected or more natural English version when helpful.
            """
        }
    }
}

nonisolated struct AgentSettings: Codable, Sendable {
    var model: String?
    var effort: String?
    var lessonsPerSection = 1
    var exercisesPerLesson = 24
    var reviewExercises = 8
    var cardsPerSection = 10
    var testExercises = 22
    var passingPercent = 80
    var prompts: [String: String] = [:]

    var snapshot: Self {
        var copy = self
        for kind in TutorPrompt.allCases { copy.prompts[kind.rawValue] = template(kind) }
        return copy
    }

    var variables: [String: Int] {
        ["lessonsPerSection": lessonsPerSection, "exercisesPerLesson": exercisesPerLesson,
         "reviewExercises": reviewExercises, "cardsPerSection": cardsPerSection,
         "testExercises": testExercises, "passingPercent": passingPercent]
    }

    var sectionSummary: String {
        "Уроков — \(lessonsPerSection), домашних работ — 1, повторений — 1. Карточек — \(cardsPerSection)."
    }

    func template(_ kind: TutorPrompt) -> String { prompts[kind.rawValue] ?? kind.original }

    func render(_ template: String) throws -> String {
        let rendered = variables.reduce(template) { text, item in
            text.replacingOccurrences(of: "{{\(item.key)}}", with: String(item.value))
        }
        guard !rendered.trimmed.isEmpty, !rendered.contains("{{"), !rendered.contains("}}") else {
            throw CourseError.invalid("Введи текст и проверь названия переменных в двойных фигурных скобках.")
        }
        return rendered
    }

    func selection(from models: [TutorModel]) throws -> TutorSelection {
        let selected: TutorModel?
        if let model {
            selected = models.first { $0.model == model }
        } else {
            selected = models.first { $0.model == "gpt-6.2-sol" } ?? models.first(where: \.isDefault) ?? models.first
        }
        guard let selected else {
            throw CourseError.invalid("Выбранная модель недоступна. Проверь каталог в настройках агента.")
        }
        let levels = selected.supportedReasoningEfforts.map(\.reasoningEffort)
        let chosen = effort ?? (levels.contains("low") ? "low" : selected.defaultReasoningEffort)
        guard levels.isEmpty ? chosen == selected.defaultReasoningEffort : levels.contains(chosen) else {
            throw CourseError.invalid("Этот уровень рассуждения недоступен. Выбери другой в настройках агента.")
        }
        return TutorSelection(model: selected.model, effort: chosen)
    }
}

nonisolated struct TutorConfiguration: Codable, Sendable {
    let settings: AgentSettings
    let selection: TutorSelection

    static func resolve(_ settings: AgentSettings, executablePath: String) async throws -> Self {
        let models = try await CodexReviewer.models(executablePath: executablePath)
        return try Self(settings: settings.snapshot, selection: settings.selection(from: models))
    }
}
