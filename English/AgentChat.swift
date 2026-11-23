import Foundation
import Observation

nonisolated struct AgentChat: Codable, Identifiable {
    struct Message: Codable, Identifiable {
        enum Role: String, Codable { case user, assistant }

        var id = UUID()
        let role: Role
        let text: String
        var lessonIDs: [String] = []
    }

    var id = UUID()
    var updatedAt = Date.now
    var messages: [Message] = []
    var generation: ChatSectionRequest?

    var title: String {
        guard let first = messages.first else { return "Новый чат" }
        let line = first.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > 64 ? String(line.prefix(63)).trimmed + "…" : line
    }
}

@Observable
final class AgentChatModel {
    enum Stage: String {
        case connecting = "Подключается к Codex…"
        case replying = "Готовит ответ…"
        case generating = "Создаёт материалы для урока…"
    }

    private(set) var chats: [AgentChat] = []
    private(set) var stages: [UUID: Stage] = [:]
    private(set) var errors: [UUID: String] = [:]
    private(set) var storageError: String?
    @ObservationIgnored private var store: CourseStore?

    var activeChat: AgentChat? { chats.first { stages[$0.id] != nil } }

    func load(executablePath: String, study: StudyModel) {
        guard store == nil else { return }
        do {
            let database = try CourseStore()
            chats = try database.agentChats()
            store = database
            storageError = nil
            for chat in chats where chat.generation != nil {
                run(chat, executablePath: executablePath, study: study, retry: false)
            }
        } catch {
            storageError = error.localizedDescription
        }
    }

    func send(_ input: String, to id: UUID?, executablePath: String, study: StudyModel) -> UUID? {
        let text = input.trimmed
        guard !text.isEmpty else { return nil }
        load(executablePath: executablePath, study: study)
        guard store != nil else { return nil }

        var chat = AgentChat()
        if let id {
            guard stages[id] == nil, let existing = chats.first(where: { $0.id == id }) else { return nil }
            chat = existing
        }
        chat.messages.append(.init(role: .user, text: text))
        chat.generation = nil
        do {
            try save(chat)
            run(chat, executablePath: executablePath, study: study, retry: false)
            return chat.id
        } catch {
            if let id {
                errors[id] = error.localizedDescription
            } else {
                storageError = error.localizedDescription
            }
            return nil
        }
    }

    func retry(_ chat: AgentChat, executablePath: String, study: StudyModel) {
        guard chat.messages.last?.role == .user else { return }
        run(chat, executablePath: executablePath, study: study, retry: true)
    }

    private func save(_ chat: AgentChat) throws {
        guard let store else { throw CourseError.storage("История чатов недоступна.") }
        var updated = chat
        updated.updatedAt = .now
        try store.saveAgentChat(updated)
        chats.removeAll { $0.id == updated.id }
        chats.insert(updated, at: 0)
        storageError = nil
    }

    private func run(_ original: AgentChat, executablePath: String, study: StudyModel, retry: Bool) {
        let id = original.id
        guard stages[id] == nil, let message = original.messages.last, message.role == .user else { return }
        stages[id] = original.generation == nil ? .connecting : .generating
        errors[id] = nil
        Task {
            defer { stages[id] = nil }
            var chat = original
            do {
                if chat.generation == nil {
                    let configuration = try await TutorConfiguration.resolve(study.agentSettings, executablePath: executablePath)
                    stages[id] = .replying
                    let response = try await AgentChatService.reply(
                        to: chat, level: study.studyLevel, course: study.snapshot,
                        executablePath: executablePath, selection: configuration.selection
                    )
                    if let generation = response.generation {
                        chat.generation = generation
                        try save(chat)
                    } else {
                        chat.messages.append(.init(role: .assistant, text: response.reply))
                        try save(chat)
                    }
                }

                if let request = chat.generation {
                    stages[id] = .generating
                    let lessonIDs = try await AgentChatService.generate(request, executablePath: executablePath, retry: retry)
                    study.refresh()
                    chat.messages.append(.init(role: .assistant,
                                               text: "Материалы по теме «\(request.topic)» добавлены в план обучения.",
                                               lessonIDs: lessonIDs))
                    chat.generation = nil
                    try save(chat)
                }
            } catch {
                errors[id] = error.localizedDescription
            }
        }
    }
}

private nonisolated enum AgentChatService {
    struct Result {
        let reply: String
        let generation: ChatSectionRequest?
    }

    private struct Reply: Decodable {
        struct Generation: Decodable {
            let topic: String
            let goal: String
            let note: String
            let moduleId: String?
            let sectionId: String?
        }

        let reply: String
        let generation: Generation?
    }

    private struct Context: Encodable {
        struct Section: Encodable {
            let moduleId: String
            let moduleTitle: String
            let sectionId: String
            let sectionTitle: String
        }

        struct Message: Encodable {
            let role: AgentChat.Message.Role
            let text: String
        }

        let level: String
        let sections: [Section]
        let messages: [Message]
    }

    @concurrent
    static func reply(to chat: AgentChat, level: String, course: CourseSnapshot,
                      executablePath: String, selection: TutorSelection) async throws -> Result {
        guard let latest = chat.messages.last else { throw invalidResponse }
        let sections = course.sections.compactMap { section -> Context.Section? in
            guard let entry = section.entries.first else { return nil }
            return .init(moduleId: entry.module.id, moduleTitle: entry.module.title,
                         sectionId: entry.section.id, sectionTitle: entry.section.title)
        }
        let recent = chat.messages.dropLast().suffix(24).map {
            Context.Message(role: $0.role, text: String($0.text.prefix(3_000)))
        }
        let context = Context(level: level, sections: sections,
                              messages: recent + [.init(role: latest.role, text: latest.text)])
        let raw = try await CodexReviewer.request(
            prompt: String(decoding: JSONEncoder().encode(context), as: UTF8.self),
            executablePath: executablePath, schema: JSONSerialization.data(withJSONObject: schema),
            instructions: """
            Reply to the latest user message in the conversation. Use prior messages for context.
            Help with English learning and questions about the course. Use the learner's language and
            match their level when giving English examples. For an ordinary reply, set generation to null
            and write the answer in reply. Markdown is supported.

            Set generation only when the learner asks you to create or add a full English lesson,
            homework, or section in English Practice. Short drills and examples requested in chat go
            in reply. If the topic is unclear, ask a concise follow-up question. Infer a practical
            learning goal when the topic and intent are clear. Supply topic, goal and any extra
            teaching requirements in note. Use the supplied course identifiers if the learner wants
            to add to a matching section. Otherwise both IDs must be null. The app runs generation
            and reports its result. When setting generation, leave reply empty.
            """,
            purpose: .chat, selection: selection
        )
        guard let response = try? JSONDecoder().decode(Reply.self, from: Data(raw.utf8)) else { throw invalidResponse }
        if let generation = response.generation {
            let topic = generation.topic.trimmed
            let goal = generation.goal.trimmed
            guard !topic.isEmpty, !goal.isEmpty,
                  (generation.moduleId == nil) == (generation.sectionId == nil),
                  generation.sectionId == nil || sections.contains(where: {
                      $0.moduleId == generation.moduleId && $0.sectionId == generation.sectionId
                  }) else { throw invalidResponse }
            return Result(reply: "", generation: .init(
                requestId: latest.id, topic: topic, goal: goal, moduleId: generation.moduleId,
                sectionId: generation.sectionId, note: generation.note.trimmed
            ))
        }
        guard !response.reply.trimmed.isEmpty else { throw invalidResponse }
        return Result(reply: response.reply.trimmed, generation: nil)
    }

    @concurrent
    static func generate(_ request: ChatSectionRequest, executablePath: String, retry: Bool) async throws -> [String] {
        let store = try CourseStore()
        var job = try store.startChatGeneration(request, executablePath: executablePath, retry: retry)
        while job.status == .running {
            let wasRunning = job.workerIsAlive
            if wasRunning { try await Task.sleep(for: .seconds(1)) }
            guard let latest = try store.chatGeneration(request.requestId) else {
                throw CourseError.storage("Запрос генерации не найден.")
            }
            guard wasRunning || latest.status != .running || latest.workerIsAlive else {
                throw CourseError.invalid("Генерация прервалась. Запрос можно повторить.")
            }
            job = latest
        }
        guard job.status == .completed else {
            throw CourseError.invalid(job.message ?? "Генерация прервалась. Запрос можно повторить.")
        }
        return job.lessonIDs
    }

    private static var invalidResponse: CourseError {
        .invalid("Codex вернул неполный ответ. Запрос можно повторить.")
    }

    private static var schema: [String: Any] {
        let string = ["type": "string"]
        let optionalString = ["type": ["string", "null"]]
        let generation: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "required": ["topic", "goal", "note", "moduleId", "sectionId"],
            "properties": ["topic": string, "goal": string, "note": string,
                           "moduleId": optionalString, "sectionId": optionalString]
        ]
        return [
            "type": "object", "additionalProperties": false, "required": ["reply", "generation"],
            "properties": ["reply": string, "generation": ["anyOf": [generation, ["type": "null"]]]]
        ]
    }
}
