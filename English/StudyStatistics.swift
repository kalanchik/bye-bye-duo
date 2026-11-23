import Foundation

nonisolated enum AgentPurpose: String, CaseIterable {
    case review, placement, plan, checkpoint, levelTest, chat

    var title: String {
        switch self {
        case .review: "Проверка ответов"
        case .placement: "Входной тест"
        case .plan: "Создание учебного плана"
        case .checkpoint: "Подготовка контрольной"
        case .levelTest: "Подготовка теста уровня"
        case .chat: "Чат с агентом"
        }
    }
}

nonisolated struct AgentTokens: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
}

nonisolated struct AgentUsage: Sendable {
    let purpose: AgentPurpose
    let requests: Int
    let measured: Int
    let input: Int
    let output: Int
    let total: Int
}

nonisolated enum ActivityPeriod: Int, CaseIterable {
    case week = 7, month = 30, quarter = 90

    var title: String { "\(rawValue) дней" }
    var binSize: Int { self == .quarter ? 7 : 1 }
}

nonisolated struct ActivityBin: Identifiable {
    let start: Date
    let end: Date
    var count = 0
    var id: Date { start }
}

extension CourseSnapshot {
    nonisolated func activity(_ period: ActivityPeriod, placement: Attempt?, now: Date = .now,
                              calendar: Calendar = .current) -> [ActivityBin] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: 1 - period.rawValue, to: today) else { return [] }
        var bins = stride(from: 0, to: period.rawValue, by: period.binSize).compactMap { offset -> ActivityBin? in
            guard let first = calendar.date(byAdding: .day, value: offset, to: start),
                  let last = calendar.date(byAdding: .day, value: min(offset + period.binSize, period.rawValue) - 1,
                                           to: start) else { return nil }
            return ActivityBin(start: first, end: last)
        }

        func count(_ date: Date, _ value: Int = 1) {
            guard date >= start, date <= now,
                  let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day,
                  bins.indices.contains(days / period.binSize) else { return }
            bins[days / period.binSize].count += value
        }

        func countAttempt(_ attempt: Attempt) {
            if let checks = attempt.checks {
                for check in checks { count(check.date) }
            } else {
                count(attempt.date, attempt.feedback.count)
            }
        }
        for progress in progress.values {
            for attempt in progress.attempts { countAttempt(attempt) }
            for check in progress.practice?.checks ?? [] { count(check.date) }
        }
        if let placement { countAttempt(placement) }
        for (date, amount) in extraVocabularyChecks { count(date, amount) }
        return bins
    }
}
