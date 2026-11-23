import Foundation
import SQLite3

nonisolated final class CourseStore {
    private let database: OpaquePointer

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = if let path = environment["ENGLISH_DATA_DIR"], !path.isEmpty {
            URL(fileURLWithPath: path, isDirectory: true)
        } else {
            try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appending(path: "English Practice", directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let path = directory.appending(path: "course.sqlite3").path
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw CourseError.storage("Не удалось открыть учебную базу.")
        }
        database = handle
        sqlite3_busy_timeout(database, 2_000)
        do {
            try execute("""
                PRAGMA foreign_keys = ON;
                CREATE TABLE IF NOT EXISTS modules (id TEXT PRIMARY KEY, data TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS sections (
                    module_id TEXT NOT NULL REFERENCES modules(id),
                    id TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY (module_id, id)
                );
                CREATE TABLE IF NOT EXISTS lessons (
                    id TEXT PRIMARY KEY, module_id TEXT NOT NULL, section_id TEXT NOT NULL, data TEXT NOT NULL,
                    FOREIGN KEY (module_id, section_id) REFERENCES sections(module_id, id)
                );
                CREATE TABLE IF NOT EXISTS progress (
                    lesson_id TEXT PRIMARY KEY REFERENCES lessons(id), data TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS study_intervals (
                    id TEXT PRIMARY KEY, lesson_id TEXT NOT NULL REFERENCES lessons(id),
                    started_at REAL NOT NULL, ended_at REAL NOT NULL CHECK (ended_at >= started_at)
                );
                CREATE INDEX IF NOT EXISTS study_intervals_end ON study_intervals(ended_at);
                CREATE TABLE IF NOT EXISTS vocabulary (
                    module_id TEXT NOT NULL, section_id TEXT NOT NULL, id TEXT NOT NULL,
                    data TEXT NOT NULL, review TEXT,
                    PRIMARY KEY (module_id, section_id, id),
                    FOREIGN KEY (module_id, section_id) REFERENCES sections(module_id, id)
                );
                CREATE TABLE IF NOT EXISTS vocabulary_practice_days (day_start REAL PRIMARY KEY);
                CREATE TABLE IF NOT EXISTS vocabulary_check_counts (
                    day_start REAL PRIMARY KEY, checks INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS agent_requests (
                    id TEXT PRIMARY KEY, purpose TEXT NOT NULL, input_tokens INTEGER,
                    output_tokens INTEGER, total_tokens INTEGER
                );
                CREATE TABLE IF NOT EXISTS agent_settings (id INTEGER PRIMARY KEY CHECK (id = 1), data TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS agent_chats (id TEXT PRIMARY KEY, data TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS chat_generations (id TEXT PRIMARY KEY, data TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS planning_state (
                    id INTEGER PRIMARY KEY CHECK (id = 1), data TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS learning_setup (
                    id INTEGER PRIMARY KEY CHECK (id = 1), data TEXT NOT NULL
                );
                """)
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    func seedIfNeeded() throws {
        try transaction {
            let hasLessons = try rows("SELECT id FROM lessons LIMIT 1") { _ in true }
            if hasLessons.isEmpty {
                for entry in DemoCourse.entries {
                    try insert(entry)
                }
            }
            for entry in DemoCourse.followUpEntries {
                let exists = try rows("SELECT id FROM lessons WHERE id = ?", [entry.lesson.id]) { _ in true }
                if exists.isEmpty {
                    try entry.validate()
                    try insert(entry)
                } else if entry.lesson.id == "present-continuous-checkpoint" {
                    try upgradeContinuousCheckpoint(entry)
                }
            }
            for (sectionID, cards) in DemoCourse.vocabulary {
                for card in cards {
                    try write("INSERT OR IGNORE INTO vocabulary (module_id, section_id, id, data) VALUES (?, ?, ?, ?)",
                              ["present-tenses", sectionID, card.id, try encode(card)])
                    if card.acceptedAnswers != nil {
                        var legacy = card
                        legacy.acceptedAnswers = nil
                        try write("UPDATE vocabulary SET data = ? WHERE module_id = ? AND section_id = ? AND id = ? AND data = ?",
                                  [try encode(card), "present-tenses", sectionID, card.id, try encode(legacy)])
                    }
                }
            }
        }
    }

    @discardableResult
    func add(_ entry: CourseEntry) throws -> Bool {
        try entry.validate()
        return try transaction { try addEntry(entry) }
    }

    private func addEntry(_ entry: CourseEntry) throws -> Bool {
        let data = try encodeLesson(entry.lesson)
        let existing = try rows(
            "SELECT module_id, section_id, data FROM lessons WHERE id = ?", [entry.lesson.id]
        ) { statement -> (module: String, section: String, canonical: String, stored: String) in
            let stored = try decodeLesson(column: 2, of: statement)
            return (column(0, of: statement), column(1, of: statement), try encodeLesson(stored), column(2, of: statement))
        }
        if let previous = existing.first {
            guard previous.module == entry.module.id, previous.section == entry.section.id, previous.canonical == data else {
                throw CourseError.invalid("ID \(entry.lesson.id) уже занят. Выбери другой ID для нового урока.")
            }
            if previous.stored != data {
                try write("UPDATE lessons SET data = ? WHERE id = ?", [data, entry.lesson.id])
            }
            return false
        }
        try insert(entry, lessonData: data)
        return true
    }

    func loadAgentSettings() throws -> AgentSettings {
        try rows("SELECT data FROM agent_settings WHERE id = 1") {
            try decode(AgentSettings.self, column: 0, of: $0)
        }.first ?? AgentSettings()
    }

    func saveAgentSettings(_ settings: AgentSettings) throws {
        try write("INSERT OR REPLACE INTO agent_settings VALUES (1, ?)", [try encode(settings)])
    }

    func agentChats() throws -> [AgentChat] {
        try rows("SELECT data FROM agent_chats") {
            try decode(AgentChat.self, column: 0, of: $0)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveAgentChat(_ chat: AgentChat) throws {
        try write("""
            INSERT INTO agent_chats (id, data) VALUES (?, ?)
            ON CONFLICT (id) DO UPDATE SET data = excluded.data
            """, [chat.id.uuidString, try encode(chat)])
    }

    func chatGeneration(_ id: UUID) throws -> ChatGeneration? {
        try rows("SELECT data FROM chat_generations WHERE id = ?", [id.uuidString]) {
            try decode(ChatGeneration.self, column: 0, of: $0)
        }.first
    }

    func saveChatGeneration(_ job: ChatGeneration) throws {
        try write("INSERT OR REPLACE INTO chat_generations VALUES (?, ?)", [job.request.requestId.uuidString, try encode(job)])
    }

    func startChatGeneration(_ request: ChatSectionRequest, executablePath: String, retry: Bool) throws -> ChatGeneration {
        try transaction {
            var job: ChatGeneration
            if let existing = try chatGeneration(request.requestId) {
                guard existing.request == request else { throw CourseError.invalid("Этот requestId занят другим запросом.") }
                job = existing
                if job.status == .completed || !retry { return job }
                if job.status == .running && job.workerIsAlive { return job }
                job.executablePath = executablePath
            } else {
                job = try ChatGeneration(request: request, settings: loadAgentSettings().snapshot, executablePath: executablePath)
            }
            guard let executable = Bundle.main.executableURL else { throw CourseError.storage("Исполняемый файл приложения не найден.") }
            let worker = Process()
            worker.executableURL = executable
            worker.arguments = ["--generate-section", request.requestId.uuidString]
            worker.standardInput = FileHandle.nullDevice
            worker.standardOutput = FileHandle.nullDevice
            worker.standardError = FileHandle.nullDevice
            try worker.run()
            job.workerPID = worker.processIdentifier
            job.workerStartTime = ChatGeneration.processStartTime(worker.processIdentifier)
            job.status = .running
            job.message = nil
            try saveChatGeneration(job)
            return job
        }
    }

    func workerJob(_ id: UUID) throws -> ChatGeneration {
        // Wait for the launching process to commit the PID and the settings snapshot.
        try transaction {
            guard let job = try chatGeneration(id), job.workerPID == getpid(), job.status == .running else {
                throw CourseError.storage("Запрос генерации не найден.")
            }
            return job
        }
    }

    func finishChatGeneration(_ job: ChatGeneration, section: GeneratedSection) throws {
        try transaction {
            try insertGeneratedSection(section)
            var completed = job
            completed.status = .completed
            completed.lessonIDs = section.entries.map(\.lesson.id)
            try saveChatGeneration(completed)
        }
    }

    func loadPlanningState() throws -> PlanningState {
        try rows("SELECT data FROM planning_state WHERE id = 1") {
            try decode(PlanningState.self, column: 0, of: $0)
        }.first ?? PlanningState()
    }

    func savePlanningState(_ state: PlanningState) throws {
        try write("""
            INSERT INTO planning_state (id, data) VALUES (1, ?)
            ON CONFLICT (id) DO UPDATE SET data = excluded.data
            """, [try encode(state)])
    }

    func finishSetup(_ setup: LearningSetup, planning: PlanningState) throws {
        try transaction {
            try saveLearningSetup(setup)
            try savePlanningState(planning)
        }
    }

    func commitPlan(_ sections: [GeneratedSection], state: PlanningState, requestID: UUID) throws {
        try transaction {
            let existing = try loadPlanningState()
            guard existing.draft?.id == requestID, existing.draft?.stage == .interrupted else {
                throw CourseError.storage("Черновик плана изменился. Открой его снова.")
            }
            for section in sections { try insertGeneratedSection(section) }
            try savePlanningState(state)
        }
    }

    private func insertGeneratedSection(_ section: GeneratedSection) throws {
        guard let anchor = section.entries.first else { throw CourseError.invalid("Раздел без уроков.") }
        for entry in section.entries {
            try entry.validate()
            _ = try addEntry(entry)
        }
        for card in section.vocabulary {
            try card.validate()
            try write("INSERT INTO vocabulary (module_id, section_id, id, data) VALUES (?, ?, ?, ?)",
                      [anchor.module.id, anchor.section.id, card.id, try encode(card)])
        }
    }

    func dataVersion() throws -> Int32 {
        try rows("PRAGMA data_version") { sqlite3_column_int($0, 0) }.first ?? 0
    }

    func loadLearningSetup() throws -> LearningSetup? {
        try rows("SELECT data FROM learning_setup WHERE id = 1") {
            try decode(LearningSetup.self, column: 0, of: $0)
        }.first
    }

    func saveLearningSetup(_ setup: LearningSetup) throws {
        try write("""
            INSERT INTO learning_setup (id, data) VALUES (1, ?)
            ON CONFLICT (id) DO UPDATE SET data = excluded.data
            """, [try encode(setup)])
    }

    func hasStudyHistory() throws -> Bool {
        try rows("""
            SELECT EXISTS(SELECT 1 FROM progress)
                OR EXISTS(SELECT 1 FROM study_intervals)
                OR EXISTS(SELECT 1 FROM vocabulary WHERE review IS NOT NULL)
            """) { sqlite3_column_int($0, 0) != 0 }.first ?? false
    }

    func snapshot() throws -> CourseSnapshot {
        let entries = try rows("""
            SELECT m.data, s.data, l.data FROM lessons l
            JOIN modules m ON m.id = l.module_id
            JOIN sections s ON s.module_id = l.module_id AND s.id = l.section_id
            ORDER BY m.rowid, s.rowid, l.rowid
            """) { statement in
                try CourseEntry(
                    module: decode(CourseModule.self, column: 0, of: statement),
                    section: decode(CourseSection.self, column: 1, of: statement),
                    lesson: decodeLesson(column: 2, of: statement)
                )
            }
        let progress = try rows("SELECT lesson_id, data FROM progress") { statement in
            try (column(0, of: statement), decode(Progress.self, column: 1, of: statement))
        }
        let vocabulary = try rows("""
            SELECT module_id, section_id, data, review FROM vocabulary ORDER BY rowid
            """) { statement in
                let card = try decode(VocabularyCard.self, column: 2, of: statement)
                let review = sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil : try decode(VocabularyReview.self, column: 3, of: statement)
                return ("\(column(0, of: statement))/\(column(1, of: statement))", VocabularyItem(card: card, review: review))
            }
        let vocabularyPracticeDays = try rows("SELECT day_start FROM vocabulary_practice_days") {
            Date(timeIntervalSince1970: sqlite3_column_double($0, 0))
        }
        let counts = try rows("SELECT day_start, checks FROM vocabulary_check_counts") {
            (Date(timeIntervalSince1970: sqlite3_column_double($0, 0)), Int(sqlite3_column_int64($0, 1)))
        }
        let usage = try rows("""
            SELECT purpose, COUNT(*), COUNT(total_tokens), SUM(input_tokens), SUM(output_tokens), SUM(total_tokens)
            FROM agent_requests GROUP BY purpose
            """) { row -> AgentUsage? in
            guard let purpose = AgentPurpose(rawValue: column(0, of: row)) else { return nil }
            func number(_ index: Int32) -> Int { Int(sqlite3_column_int64(row, index)) }
            return AgentUsage(purpose: purpose, requests: number(1), measured: number(2),
                              input: number(3), output: number(4), total: number(5))
        }
        return CourseSnapshot(
            entries: entries, progress: Dictionary(uniqueKeysWithValues: progress),
            vocabulary: Dictionary(grouping: vocabulary, by: { $0.0 }).mapValues { $0.map { $0.1 } },
            agentUsage: usage.compactMap { $0 }, extraVocabularyChecks: Dictionary(uniqueKeysWithValues: counts),
            vocabularyPracticeDays: Set(vocabularyPracticeDays)
        )
    }

    func addVocabulary(_ cards: [VocabularyCard], moduleID: String, sectionID: String) throws -> Int {
        guard (1...50).contains(cards.count), Set(cards.map(\.id)).count == cards.count else {
            throw CourseError.invalid("Добавь от 1 до 50 карточек с разными ID.")
        }
        for card in cards { try card.validate() }
        return try transaction {
            let section = try rows("SELECT id FROM sections WHERE module_id = ? AND id = ?", [moduleID, sectionID]) { _ in true }
            guard !section.isEmpty else { throw CourseError.invalid("Раздел не найден. Возьми ID из list_course.") }
            var count = 0
            for card in cards {
                let data = try encode(card)
                let key = [moduleID, sectionID, card.id]
                let existing = try rows(
                    "SELECT data FROM vocabulary WHERE module_id = ? AND section_id = ? AND id = ?", key
                ) { try encode(decode(VocabularyCard.self, column: 0, of: $0)) }.first
                if let existing {
                    guard existing == data else { throw CourseError.invalid("ID карточки \(card.id) уже занят.") }
                } else {
                    try write("INSERT INTO vocabulary (module_id, section_id, id, data) VALUES (?, ?, ?, ?)", key + [data])
                    count += 1
                }
            }
            return count
        }
    }

    func startAgentRequest(_ id: UUID, purpose: AgentPurpose) throws {
        try write("INSERT INTO agent_requests (id, purpose) VALUES (?, ?)", [id.uuidString, purpose.rawValue])
    }

    func updateAgentTokens(_ tokens: AgentTokens, for id: UUID) throws {
        try write("UPDATE agent_requests SET input_tokens = ?, output_tokens = ?, total_tokens = ? WHERE id = ?",
                  [String(tokens.inputTokens), String(tokens.outputTokens), String(tokens.totalTokens), id.uuidString])
    }

    func saveVocabularyReviews(_ reviews: [String: VocabularyReview], moduleID: String, sectionID: String,
                               practiceDay: Date, extraCheck: Bool, progress: Progress? = nil,
                               lessonID: String) throws {
        try transaction {
            for (cardID, review) in reviews {
                try write("UPDATE vocabulary SET review = ? WHERE id = ? AND module_id = ? AND section_id = ?",
                          [try encode(review), cardID, moduleID, sectionID])
            }
            let day = [String(practiceDay.timeIntervalSince1970)]
            try write("INSERT OR IGNORE INTO vocabulary_practice_days (day_start) VALUES (?)", day)
            if extraCheck {
                try write("""
                    INSERT INTO vocabulary_check_counts (day_start, checks) VALUES (?, 1)
                    ON CONFLICT(day_start) DO UPDATE SET checks = checks + 1
                    """, day)
            }
            if let progress { try save(progress, for: lessonID) }
        }
    }

    func save(_ progress: Progress, for lessonID: String) throws {
        try write("""
            INSERT INTO progress (lesson_id, data) VALUES (?, ?)
            ON CONFLICT (lesson_id) DO UPDATE SET data = excluded.data
            """, [lessonID, try encode(progress)])
    }

    func studySeconds(for lessonID: String, since: Date) throws -> TimeInterval {
        try rows("""
            SELECT COALESCE(SUM(ended_at - MAX(started_at, CAST(? AS REAL))), 0)
            FROM study_intervals WHERE lesson_id = ? AND ended_at > CAST(? AS REAL)
            """, [String(since.timeIntervalSince1970), lessonID, String(since.timeIntervalSince1970)]) {
            sqlite3_column_double($0, 0)
        }.first ?? 0
    }

    func saveStudy(_ interval: StudyInterval) throws {
        guard interval.end > interval.start else { return }
        try write("""
            INSERT INTO study_intervals (id, lesson_id, started_at, ended_at) VALUES (?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET ended_at = MAX(ended_at, excluded.ended_at)
            """, [
                interval.id.uuidString, interval.lessonID,
                String(interval.start.timeIntervalSince1970), String(interval.end.timeIntervalSince1970)
            ])
    }

    func studySeconds(in day: DateInterval) throws -> TimeInterval {
        let start = String(day.start.timeIntervalSince1970)
        let end = String(day.end.timeIntervalSince1970)
        return try rows("""
            SELECT COALESCE(SUM(MIN(ended_at, CAST(? AS REAL)) - MAX(started_at, CAST(? AS REAL))), 0)
            FROM study_intervals WHERE started_at < ? AND ended_at > ?
            """, [end, start, end, start]) { sqlite3_column_double($0, 0) }.first ?? 0
    }

    private func insert(_ entry: CourseEntry, lessonData: String? = nil) throws {
        try write("INSERT OR IGNORE INTO modules (id, data) VALUES (?, ?)",
                  [entry.module.id, try encode(entry.module)])
        try write("INSERT OR IGNORE INTO sections (module_id, id, data) VALUES (?, ?, ?)",
                  [entry.module.id, entry.section.id, try encode(entry.section)])
        try write("INSERT INTO lessons (id, module_id, section_id, data) VALUES (?, ?, ?, ?)",
                  [entry.lesson.id, entry.module.id, entry.section.id, try lessonData ?? encodeLesson(entry.lesson)])
    }

    private func encodeLesson(_ lesson: Lesson) throws -> String {
        // Older MCP processes can read these lessons while the application is being updated.
        var stored = lesson
        if stored.kind == .story { stored.kind = .lesson }
        for index in stored.exercises.indices {
            let kind = stored.exercises[index].kind
            switch kind {
            case .wordOrder:
                stored.exercises[index].kind = .gap
            case .translationTiles, .translationCard, .translationPairs, .translationChoice:
                stored.exercises[index].storedFormat = kind
                stored.exercises[index].kind = kind.usesChoices ? .choice : .gap
            default: break
            }
        }
        return try encode(stored)
    }

    private func decodeLesson(column index: Int32, of statement: OpaquePointer) throws -> Lesson {
        var lesson = try decode(Lesson.self, column: index, of: statement)
        if lesson.story != nil { lesson.kind = .story }
        for index in lesson.exercises.indices {
            if let format = lesson.exercises[index].storedFormat {
                lesson.exercises[index].kind = format
                lesson.exercises[index].storedFormat = nil
            } else if lesson.exercises[index].kind == .gap, lesson.exercises[index].words != nil {
                lesson.exercises[index].kind = .wordOrder
            }
        }
        return lesson
    }

    private func upgradeContinuousCheckpoint(_ entry: CourseEntry) throws {
        let legacy = try rows("""
            SELECT data FROM lessons WHERE id = ? AND module_id = ? AND section_id = ?
            AND NOT EXISTS (SELECT 1 FROM progress WHERE lesson_id = lessons.id)
            """, [entry.lesson.id, entry.module.id, entry.section.id]) {
                try decode(Lesson.self, column: 0, of: $0)
            }.first
        guard let legacy, legacy.passingPercent == 80,
              legacy.exercises.map(\.id) == ["am", "are", "ing", "question", "hear"] else { return }
        try entry.validate()
        try write("UPDATE lessons SET data = ? WHERE id = ?", [try encode(entry.lesson), entry.lesson.id])
    }

    private func transaction<Value>(_ operation: () throws -> Value) throws -> Value {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try operation()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw databaseError }
    }

    private func write(_ sql: String, _ values: [String]) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError }
    }

    private func rows<Value>(
        _ sql: String, _ values: [String] = [], decode row: (OpaquePointer) throws -> Value
    ) throws -> [Value] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [Value] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            result.append(try row(statement))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw databaseError }
        return result
    }

    private func prepare(_ sql: String, _ values: [String]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw databaseError
            }
        }
        return statement
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, column index: Int32, of statement: OpaquePointer) throws -> Value {
        try JSONDecoder().decode(type, from: Data(column(index, of: statement).utf8))
    }

    private func column(_ index: Int32, of statement: OpaquePointer) -> String {
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }

    private var databaseError: CourseError {
        .storage("Учебная база: \(String(cString: sqlite3_errmsg(database)))")
    }
}
