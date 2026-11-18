import Foundation

nonisolated struct LearningSetup: Codable, Sendable {
    enum Stage: String, Codable, Sendable {
        case agent, motivation, level, format, goal, reminders, testIntro, test, result, complete

        var number: Int {
            switch self {
            case .agent: 1
            case .motivation: 2
            case .level: 3
            case .format: 4
            case .goal: 5
            case .reminders: 6
            case .testIntro, .test, .result, .complete: 7
            }
        }

        var label: String {
            switch self {
            case .agent: "Подключение"
            case .motivation: "Мотивация"
            case .level: "Уровень"
            case .format: "Формат занятий"
            case .goal: "Дневная цель"
            case .reminders: "Напоминания"
            case .testIntro, .test, .result, .complete: "Входной тест"
            }
        }
    }

    enum Motivation: String, Codable, CaseIterable, Sendable {
        case travel = "Для путешествий"
        case work = "Для работы и карьеры"
        case communication = "Для общения"
        case study = "Для учёбы"
        case personal = "Для себя"
        case other = "Другая причина"
    }

    enum SelfAssessment: String, Codable, CaseIterable, Sendable {
        case zero = "Начинаю с нуля"
        case phrases = "Знаю отдельные слова и фразы"
        case simple = "Могу поддержать простой разговор"
        case varied = "Могу говорить на разные темы"
        case confident = "Уверенно общаюсь на английском"
    }

    var stage: Stage = .agent
    var motivation: Motivation?
    var selfAssessment: SelfAssessment?
    var presetMinutes: Int? = 10
    var customMinutes = ""
    var reminderEnabled: Bool?
    var questionID: String?
    var answers: [String: String] = [:]
    var result: PlacementResult?

    var goalMinutes: Int? {
        let minutes = presetMinutes ?? Int(customMinutes)
        return minutes.flatMap { (1...180).contains($0) ? $0 : nil }
    }
}

nonisolated struct PlacementResult: Codable, Sendable {
    enum Skill: String, Codable, CaseIterable, Sendable {
        case grammar = "Грамматика"
        case reading = "Понимание текста"
        case listening = "Аудирование"
        case writing = "Письмо"
    }

    struct Score: Codable, Sendable {
        let skill: Skill
        let correct: Int
        let total: Int

        var strong: Bool { total >= 3 && correct * 100 >= total * 80 }
    }

    let level: String
    let sectionID: String
    let sectionTitle: String
    let attempt: Attempt
    let scores: [Score]

    init(attempt: Attempt) {
        self.attempt = attempt
        scores = Skill.allCases.map { skill in
            let ids = Set(PlacementTest.items.filter { $0.skill == skill }.map(\.id))
            let checked = attempt.feedback.filter { ids.contains($0.id) }
            return Score(skill: skill, correct: checked.count(where: \.correct), total: checked.count)
        }
        level = "A1"
        let readyForReview = scores.allSatisfy(\.strong)
        sectionID = readyForReview ? "present-tenses/present-contrast" : "present-tenses/present-simple"
        sectionTitle = readyForReview ? "Simple или Continuous?" : "Present Simple"
    }
}

nonisolated enum PlacementTest {
    struct Item: Sendable {
        let exercise: Exercise
        let skill: PlacementResult.Skill

        var id: String { exercise.id }
    }

    static let items: [Item] = [
        choice("coffee", .grammar, "I usually ___ coffee in the morning.",
               ["drink", "drinks", "drinking"], "drink", "После I в Present Simple нужна форма drink."),
        choice("key", .reading, "Leo writes: “Your key is on the kitchen table.” Where is the key?",
               ["On the kitchen table", "In the car", "In the bedroom"], "On the kitchen table",
               "On the kitchen table означает «на кухонном столе»."),
        choice("ticket", .reading, "You want to buy a bus ticket. What do you say?",
               ["Where do you live?", "Can I have a ticket, please?", "I'm on the bus."],
               "Can I have a ticket, please?", "Can I have…? подходит для вежливой просьбы."),
        choice("water", .grammar, "There ___ two bottles of water in the bag.",
               ["is", "are", "am"], "are", "С двумя бутылками употребляем there are."),
        gap("open", .grammar, "Впиши одно слово. What time ___ the shop open?",
            ["does"], "Перед the shop в вопросе Present Simple нужна форма does."),
        choice("meeting", .reading, "Mia texts: “I can't meet at six. Can we meet at seven?” What does Mia suggest?",
               ["Meeting at five", "Meeting at six", "Meeting at seven"], "Meeting at seven",
               "At seven означает «в семь»."),
        choice("bus", .listening, "Что говорит человек?",
               ["Автобус отправляется в половине восьмого.", "Автобус приезжает в восемь.", "Автобус отправляется в семь."],
               "Автобус отправляется в половине восьмого.", "Leaves at half past seven означает «отправляется в 7:30».",
               audio: "The bus leaves at half past seven."),
        choice("station", .listening, "Что говорит человек?",
               ["Она живёт рядом со станцией.", "Она ждёт на станции.", "Она работает на станции."],
               "Она живёт рядом со станцией.", "Lives near the station означает «живёт рядом со станцией».",
               audio: "She lives near the station."),
        choice("milk", .listening, "Что говорит человек?",
               ["Купи хлеб.", "У нас кончилось молоко.", "Я не пью молоко."],
               "У нас кончилось молоко.", "We don't have any milk left означает, что молока больше нет.",
               audio: "We don't have any milk left."),
        choice("shop", .listening, "Что говорит человек?",
               ["Магазин закрывается в пятницу.", "Магазин открыт до шести.", "Магазин рядом с аптекой."],
               "Магазин открыт до шести.", "Open until six означает «открыт до шести».",
               audio: "The shop is open until six."),
        choice("park", .reading, "The sign says: “Keep dogs on a lead.” What should you do?",
               ["Keep your dog on a lead", "Leave your dog outside", "Let your dog run free"], "Keep your dog on a lead",
               "On a lead означает «на поводке»."),
        gap("sister", .reading, "Впиши слово «сестра» по-английски. This is my ___.",
            ["sister"], "Sister означает «сестра»."),
        choice("rain", .grammar, "Look! It ___ outside.",
               ["rains every day", "is raining", "rain"], "is raining", "Дождь идёт прямо сейчас, поэтому подходит is raining."),
        choice("pharmacy", .reading, "Go straight and turn left at the pharmacy. Where do you turn?",
               ["At the pharmacy", "At the station", "At the bank"], "At the pharmacy",
               "At the pharmacy означает «у аптеки»."),
        gap("lunch", .grammar, "Впиши одно слово. We usually eat lunch ___ noon.",
            ["at"], "С точным временем употребляем at noon."),
        choice("yesterday", .grammar, "Yesterday we ___ a film at home.",
               ["watch", "watched", "are watching"], "watched", "Yesterday указывает на прошлое, поэтому подходит watched."),
        written("introduce", "Say hello and tell a new classmate your name.",
                "Есть приветствие и представление по имени. Принимай естественные фразы с любым именем."),
        written("cafe", "Ask for a glass of water in a café.",
                "Вежливая или нейтральная просьба дать стакан воды. Принимай Can I have…, Could I get… и другие естественные просьбы."),
        written("late", "Your friend texts: “Are you here?” Say you are ten minutes late.",
                "Сообщение передаёт опоздание на десять минут или прибытие на десять минут позже. Принимай естественные варианты."),
        written("after-work", "What do you usually do after work?",
                "Одна или две понятные фразы об обычном занятии после работы или учёбы. Подходит любой естественный ответ о распорядке.")
    ]

    static var lesson: Lesson {
        Lesson(id: "placement-v1", title: "Входной тест English Practice", kind: .lesson, theory: "",
               estimatedMinutes: nil, timeLimitMinutes: nil, exercises: items.map(\.exercise))
    }

    static func grade(_ answers: [String: String], executablePath: String) async throws -> PlacementResult {
        guard items.allSatisfy({ answers[$0.id]?.trimmed.isEmpty == false }) else {
            throw CourseError.invalid("Ответь на все задания входного теста.")
        }
        let questions = items.compactMap { item -> CodexReviewer.Question? in
            guard let rubric = item.exercise.rubric, let answer = answers[item.id] else { return nil }
            return .init(id: item.id, prompt: item.exercise.prompt, rubric: rubric, answer: answer)
        }
        let written = try await CodexReviewer.review(lesson: lesson, questions: questions, executablePath: executablePath, purpose: .placement)
        let byID = Dictionary(uniqueKeysWithValues: written.map { ($0.id, $0) })
        let feedback = items.map { item in byID[item.id] ?? item.exercise.grade(answers[item.id] ?? "") }
        return PlacementResult(attempt: Attempt(answers: answers, feedback: feedback))
    }

    private static func choice(
        _ id: String, _ skill: PlacementResult.Skill, _ prompt: String,
        _ options: [String], _ answer: String, _ explanation: String, audio: String? = nil
    ) -> Item {
        Item(exercise: Exercise(id: id, kind: .choice, prompt: prompt, options: options, acceptedAnswers: [answer],
                                explanation: explanation, rubric: nil, topic: nil, speechText: audio), skill: skill)
    }

    private static func gap(
        _ id: String, _ skill: PlacementResult.Skill, _ prompt: String, _ answers: [String], _ explanation: String
    ) -> Item {
        Item(exercise: Exercise(id: id, kind: .gap, prompt: prompt, options: nil, acceptedAnswers: answers,
                                explanation: explanation, rubric: nil, topic: nil), skill: skill)
    }

    private static func written(_ id: String, _ prompt: String, _ rubric: String) -> Item {
        Item(exercise: Exercise(id: id, kind: .written, prompt: prompt, options: nil, acceptedAnswers: nil,
                                explanation: nil, rubric: rubric, topic: nil), skill: .writing)
    }
}
