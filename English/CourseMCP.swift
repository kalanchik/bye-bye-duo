import Foundation

enum CourseMCP {
    private struct VocabularyArguments: Decodable {
        let moduleId: String
        let sectionId: String
        let cards: [VocabularyCard]
    }

    static func run() {
        var store: CourseStore?
        while let line = readLine() {
            let data = Data(line.utf8)
            guard data.count <= 256_000,
                  let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                send(["id": NSNull(), "error": ["code": -32700, "message": "Invalid JSON-RPC message."]])
                continue
            }
            guard let id = message["id"] else { continue }
            let params = message["params"] as? [String: Any] ?? [:]
            let result: [String: Any]
            switch message["method"] as? String {
            case "initialize":
                let requested = params["protocolVersion"] as? String ?? ""
                let versions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
                result = [
                    "protocolVersion": versions.contains(requested) ? requested : versions[0],
                    "capabilities": ["tools": [:]],
                    "serverInfo": ["name": "english-practice", "version": "1.0.0"],
                    "instructions": """
                    Use list_course to find the module and section IDs before adding English lessons or homework.
                    Use add_lesson to save directly to the learner’s macOS app. Provide short theory, prompts,
                    answer keys and explanations for closed exercises, and rubrics for written answers or dialogue.
                    Use get_study_context to review the learner’s latest checked attempt and plan follow-up practice.
                    Use add_vocabulary to add English and Russian pairs with example sentences to a section.
                    """
                ]
            case "ping":
                result = [:]
            case "tools/list":
                result = ["tools": toolDefinitions]
            case "tools/call":
                do {
                    if store == nil {
                        let opened = try CourseStore()
                        try opened.seedIfNeeded()
                        store = opened
                    }
                    guard let store else { continue }
                    result = toolResult(try call(params, store: store))
                } catch {
                    result = toolResult(error.localizedDescription, isError: true)
                }
            default:
                send(["id": id, "error": ["code": -32601, "message": "Method not found."]])
                continue
            }
            send(["id": id, "result": result])
        }
    }

    private static func call(_ params: [String: Any], store: CourseStore) throws -> String {
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        switch params["name"] as? String {
        case "list_course":
            let snapshot = try store.snapshot()
            let lessons: [[String: Any]] = snapshot.entries.map { entry in
                let progress = snapshot.progress[entry.lesson.id] ?? Progress()
                return [
                    "moduleId": entry.module.id, "moduleTitle": entry.module.title,
                    "sectionId": entry.section.id, "sectionTitle": entry.section.title,
                    "lessonId": entry.lesson.id, "title": entry.lesson.title,
                    "kind": entry.lesson.isCheckpoint ? "checkpoint" : entry.lesson.kind.rawValue,
                    "status": entry.lesson.status(for: progress),
                    "vocabularyCount": snapshot.vocabulary["\(entry.module.id)/\(entry.section.id)"]?.count ?? 0
                ]
            }
            return try jsonText(lessons)
        case "add_lesson":
            let entry: CourseEntry
            do {
                let data = try JSONSerialization.data(withJSONObject: arguments)
                entry = try JSONDecoder().decode(CourseEntry.self, from: data)
            } catch {
                throw CourseError.invalid("Проверь поля урока по схеме MCP: \(error)")
            }
            let created = try store.add(entry)
            return try jsonText(["id": entry.lesson.id, "title": entry.lesson.title, "created": created])
        case "add_vocabulary":
            let data = try JSONSerialization.data(withJSONObject: arguments)
            let input = try JSONDecoder().decode(VocabularyArguments.self, from: data)
            let created = try store.addVocabulary(input.cards, moduleID: input.moduleId, sectionID: input.sectionId)
            return try jsonText(["sectionId": input.sectionId, "created": created])
        case "get_study_context":
            let snapshot = try store.snapshot()
            guard let id = arguments["lessonId"] as? String,
                  let entry = snapshot.entries.first(where: { $0.lesson.id == id }) else {
                throw CourseError.invalid("Урок не найден. Используй lessonId из list_course.")
            }
            let progress = snapshot.progress[id] ?? Progress()
            let cards = progress.attempts.last?.vocabularyCards ?? (progress.attempts.isEmpty ? progress.vocabularyCards : nil)
            let exercises: [[String: String]] = entry.lesson.includingVocabulary(cards ?? []).exercises.map {
                ["id": $0.id, "kind": $0.speechText == nil ? $0.kind.rawValue : "listening",
                 "prompt": $0.prompt, "topic": $0.topic ?? ""]
            }
            var context: [String: Any] = [
                "lessonId": id, "title": entry.lesson.title, "section": entry.section.title,
                "module": entry.module.title, "theory": entry.lesson.theory, "exercises": exercises,
                "attemptCount": progress.attempts.count, "status": entry.lesson.status(for: progress)
            ]
            if let percent = entry.lesson.passingPercent { context["passingPercent"] = percent }
            if let attempt = progress.attempts.last {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                context["latestAttempt"] = try JSONSerialization.jsonObject(with: encoder.encode(attempt))
            }
            return try jsonText(context)
        default:
            throw CourseError.invalid("Неизвестный инструмент.")
        }
    }

    private static func jsonText(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }

    private static func toolResult(_ text: String, isError: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private static func send(_ message: [String: Any]) {
        guard let line = try? jsonText(["jsonrpc": "2.0"].merging(message) { _, value in value }) else { return }
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private static func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }

    private static var toolDefinitions: [[String: Any]] {
        let string = ["type": "string"]
        let strings: [String: Any] = ["type": "array", "items": string]
        let card = object([
            "id": string, "english": string, "russian": string, "example": string, "exampleTranslation": string,
            "acceptedAnswers": strings
        ], required: ["id", "english", "russian", "example", "exampleTranslation"])
        let place = object([
            "id": string, "title": string,
            "theory": ["type": "string", "description": "Brief theory in Markdown. For an existing ID this metadata is kept."]
        ], required: ["id", "title", "theory"])
        let exercise = object([
            "id": string,
            "kind": ["type": "string", "enum": Exercise.Kind.allCases.map(\.rawValue)],
            "prompt": string,
            "options": strings, "acceptedAnswers": strings, "explanation": string,
            "rubric": string, "topic": string, "words": strings,
            "pairs": ["type": "array", "minItems": 2, "maxItems": 8,
                      "items": object(["russian": string, "english": string], required: ["russian", "english"])],
            "speechText": ["type": "string", "description": "For a listening exercise, use choice and put the English audio script here."]
        ], required: ["id", "kind", "prompt"])
        let line = object(["id": string, "speaker": string, "text": string], required: ["id", "text"])
        let scene = object([
            "id": string, "lines": ["type": "array", "items": line], "exercises": strings,
            "title": string, "instruction": string
        ], required: ["id", "lines", "exercises"])
        let story = object([
            "version": ["type": "integer", "minimum": 1],
            "scenes": ["type": "array", "items": scene]
        ], required: ["version", "scenes"])
        let lesson = object([
            "id": string, "title": string,
            "kind": ["type": "string", "enum": ["lesson", "homework", "story"]],
            "theory": string,
            "estimatedMinutes": ["type": "integer", "minimum": 1, "maximum": 240],
            "timeLimitMinutes": ["type": "integer", "minimum": 1, "maximum": 240],
            "passingPercent": ["type": "integer", "minimum": 1, "maximum": 100,
                               "description": "Set this on a section checkpoint, typically 80."],
            "exercises": ["type": "array", "items": exercise, "minItems": 1, "maxItems": 30],
            "story": story
        ], required: ["id", "title", "kind", "theory", "exercises"])
        return [
            [
                "name": "list_course",
                "description": "List modules, sections, lessons, homework and checkpoints with IDs and completion status.",
                "inputSchema": object([:], required: []),
                "annotations": ["readOnlyHint": true, "openWorldHint": false]
            ],
            [
                "name": "add_lesson",
                "description": """
                Save a lesson, homework, story or checkpoint to English Practice. Use lowercase ASCII IDs with hyphens.
                Reuse existing module and section IDs or give new ones with their theory.
                For gap, choice and correction, supply acceptedAnswers and explanation. For choice, include options.
                For written or dialogue, include a rubric. Use stable topic labels to group mistakes.
                For listening use choice with speechText. For a checkpoint use lesson with passingPercent.
                For a story supply versioned scenes with dialogue lines and ordered exercise IDs.
                For wordOrder include shuffled words, acceptedAnswers and explanation.
                For translationTiles put the source phrase in prompt and shuffle the translation words with optional distractors.
                For translationChoice give a source word in prompt and translation options. For translationCard the learner types the translation.
                For all three supply acceptedAnswers and explanation. For translationPairs supply a Russian instruction in prompt,
                2–8 unique russian/english pairs and an explanation. The pairs themselves are the answer key.
                Retrying the same lesson ID with identical lesson data is safe.
                """,
                "inputSchema": object(["module": place, "section": place, "lesson": lesson],
                                      required: ["module", "section", "lesson"]),
                "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false]
            ],
            [
                "name": "add_vocabulary",
                "description": "Add pairs to a section using its module and section IDs. Use unique lowercase IDs and a single unambiguous translation with an example in both languages.",
                "inputSchema": object([
                    "moduleId": string, "sectionId": string,
                    "cards": ["type": "array", "items": card, "minItems": 1, "maxItems": 50]
                ], required: ["moduleId", "sectionId", "cards"]),
                "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false]
            ],
            [
                "name": "get_study_context",
                "description": "Read lesson prompts and the latest submitted answers and feedback to discuss errors or prepare targeted practice.",
                "inputSchema": object(["lessonId": string], required: ["lessonId"]),
                "annotations": ["readOnlyHint": true, "openWorldHint": false]
            ]
        ]
    }
}
