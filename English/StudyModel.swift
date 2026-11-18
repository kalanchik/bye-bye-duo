import Foundation
import Observation
import UserNotifications

nonisolated enum ReminderTime {
    static func minutes(from text: String) -> Int? {
        guard let match = text.trimmed.wholeMatch(of: /([0-9]{1,2})(?::([0-9]{2}))?/),
              let hour = Int(match.1), hour < 24,
              let minute = Int(match.2 ?? "00"), minute < 60 else { return nil }
        return hour * 60 + minute
    }

    static func text(for minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

@Observable
final class StudyModel {
    let playSound: (PracticeSound) -> Void

    init(playSound: @escaping (PracticeSound) -> Void = { $0.play() }) {
        self.playSound = playSound
    }

    private static let defaultDailyGoalMinutes = 30
    static let dailyReminderID = "english-practice.daily-study"

    enum DailyReminderStatus { case off, scheduled, needsPermission, failed }

    private var store: CourseStore?
    private var dataVersion: Int32?
    private var studyDay: Date?
    private var lastStudyCheckpoint: Date?
    private var pendingStudy: [StudyInterval] = []
    private(set) var snapshot = CourseSnapshot()
    private(set) var learningSetup: LearningSetup?
    private(set) var planning = PlanningState()
    private(set) var generationPhase: Int?
    private(set) var generationError: String?
    private(set) var hasStudyHistory = false
    private(set) var checking: Set<String> = []
    private(set) var activeStudy: StudyRun?
    private(set) var todayStudySeconds: TimeInterval = 0
    private(set) var pendingStreakDay: Date?
    private(set) var dailyReminderEnabled = UserDefaults.standard.bool(forKey: "dailyReminderEnabled")
    private(set) var dailyReminderMinutes = UserDefaults.standard.object(forKey: "dailyReminderMinutes") as? Int ?? 19 * 60
    private(set) var dailyReminderStatus: DailyReminderStatus = .off
    private(set) var configuringDailyReminder = false
    var error: String?

    var dailyGoalMinutes: Int {
        learningSetup?.stage == .complete
            ? (learningSetup?.goalMinutes ?? Self.defaultDailyGoalMinutes) : Self.defaultDailyGoalMinutes
    }

    var shouldPresentOnboarding: Bool {
        guard store != nil else { return false }
        return learningSetup.map { $0.stage != .complete } ?? !hasStudyHistory
    }

    func refresh() {
        do {
            if store == nil {
                let opened = try CourseStore()
                try opened.seedIfNeeded()
                learningSetup = try opened.loadLearningSetup()
                planning = try opened.loadPlanningState()
                if learningSetup?.stage == .complete, !planning.firstPlanCreated, planning.draft == nil {
                    var initial = planning
                    initial.draft = firstPlanDraft()
                    try opened.savePlanningState(initial)
                    planning = initial
                }
                hasStudyHistory = try opened.hasStudyHistory()
                store = opened
            }
            guard let store else { return }
            let version = try store.dataVersion()
            if version != dataVersion {
                snapshot = try store.snapshot()
                dataVersion = version
            }
            try updateStudyTime(in: store, now: .now)
        } catch {
            self.error = error.localizedDescription
        }
    }

    var routeSections: [StudySection] {
        let sections = snapshot.sections
        let generatedIDs = planning.route.map(\.id)
        let planned = generatedIDs.compactMap { id in sections.first { $0.id == id } }
        let existing = sections.filter { !generatedIDs.contains($0.id) }
        return planning.firstPlanCreated ? planned + existing : existing + planned
    }

    var nextLesson: Lesson? {
        let preferred = !planning.firstPlanCreated && learningSetup?.stage == .complete
            ? learningSetup?.result?.sectionID : nil
        let ordered = routeSections.filter { $0.id == preferred } + routeSections.filter { $0.id != preferred }
        var review: Lesson?
        for section in ordered where !section.completed(snapshot.progress) {
            let steps = section.orderedEntries
            if let index = steps.firstIndex(where: {
                !$0.lesson.completed(progress(for: $0.lesson.id)) && $0.lesson.levelTest == nil
            }) {
                let lesson = steps[index].lesson
                let state = progress(for: lesson.id)
                if lesson.spacedReview == true, state.practice == nil, state.draft.isEmpty, index > 0,
                   let date = progress(for: steps[index - 1].lesson.id).attempts.last?.date,
                   Calendar.current.isDateInToday(date) {
                    review = review ?? lesson
                    continue
                }
                return lesson
            }
        }
        return review
    }

    var studyLevel: String { planning.level ?? learningSetup?.result?.level ?? "A1" }

    var levelBadge: String {
        let name = switch studyLevel {
        case "A1": "Начальный"
        case "A2": "Базовый"
        case "B1": "Средний"
        case "B2": "Выше среднего"
        case "C1": "Продвинутый"
        default: "Владение в совершенстве"
        }
        return "\(studyLevel) · \(name)"
    }

    var levelTestReadiness: (passedSections: Int, missingSkills: [PlacementResult.Skill]) {
        let currentIDs = Set(planning.route.filter { $0.level == studyLevel }.map(\.id))
        var passedSections = 0
        var skillCounts: [PlacementResult.Skill: Int] = [:]
        for section in snapshot.sections where currentIDs.contains(section.id) {
            let evidence = section.entries.filter { $0.lesson.isCheckpoint }.compactMap { entry in
                progress(for: entry.lesson.id).attempts.last(where: entry.lesson.passed)
                    .map { entry.lesson.levelEvidence(for: $0) }
            }
            if !evidence.isEmpty { passedSections += 1 }
            for score in evidence.joined() {
                skillCounts[score.skill, default: 0] += score.total
            }
        }
        return (passedSections, PlacementResult.Skill.allCases.filter { skillCounts[$0, default: 0] < 3 })
    }

    func completeOnboarding() -> Bool {
        do {
            guard let store, var setup = learningSetup, setup.result != nil else { return false }
            setup.stage = .complete
            var state = planning
            if !state.firstPlanCreated {
                state.draft = firstPlanDraft()
            }
            try store.finishSetup(setup, planning: state)
            learningSetup = setup
            planning = state
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func firstPlanDraft() -> PlanDraft {
        let recommended = StudyTopic.recommendations(for: learningSetup?.motivation)
        let selected = recommended.prefix(2).compactMap { id in StudyTopic.catalog.first { $0.id == id } }
        return PlanDraft(mode: .first, selected: selected)
    }

    @discardableResult
    func updatePlanning(_ change: (inout PlanningState) -> Void) -> Bool {
        do {
            guard let store else { throw CourseError.storage("Учебная база ещё не открылась.") }
            var state = planning
            change(&state)
            try store.savePlanningState(state)
            planning = state
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func beginPlan(_ mode: PlanDraft.Mode, section: StudySection? = nil, deepen: Bool = false) -> Bool {
        guard generationPhase == nil else { return false }
        if planning.draft != nil {
            return true
        }
        var draft = mode == .first ? firstPlanDraft() : PlanDraft(mode: mode)
        draft.sourceSectionID = section?.id
        let source = section?.entries.first
        let storedTopic = planning.route.first { $0.id == section?.id }?.topic
        if mode == .levelTest {
            draft.selected = [.init(id: "level-test", title: "Проверка уровня \(studyLevel)",
                                    goal: "Проверить навыки на новых ситуациях")]
            draft.stage = .review
        } else if let source, deepen || mode == .checkpoint {
            let topic = storedTopic ?? StudyTopic(id: source.section.id, title: source.section.title,
                                                 goal: "Применить изученное в другой ситуации")
            draft.selected = mode == .checkpoint
                ? [.init(id: topic.id, title: "Контрольная · \(topic.title)", goal: topic.goal)] : [topic]
            draft.stage = .review
        }
        return updatePlanning { $0.draft = draft }
    }

    func acceptLevel(from lesson: Lesson) {
        guard lesson.levelTest == studyLevel, let attempt = progress(for: lesson.id).attempts.last,
              lesson.passed(attempt) else { return }
        let levels = ["A1", "A2", "B1", "B2", "C1", "C2"]
        guard let index = levels.firstIndex(of: studyLevel), levels.indices.contains(index + 1) else { return }
        updatePlanning { $0.level = levels[index + 1] }
    }

    func generatePlan(note: String, executablePath: String) async {
        guard let store, var draft = planning.draft, !draft.selected.isEmpty, generationPhase == nil else { return }
        if draft.note != note { draft.prepared = [] }
        draft.note = note
        draft.stage = .interrupted
        guard updatePlanning({ $0.draft = draft }) else { return }
        generationError = nil
        generationPhase = 0
        defer { generationPhase = nil }
        do {
            await Task.yield()
            try Task.checkCancellation()
            let level = studyLevel
            let diagnosis = learningSetup?.result?.scores.map {
                "\($0.skill.rawValue): \($0.correct)/\($0.total)"
            }.joined(separator: ", ") ?? "Ещё проверяем"
            let course = snapshot.sections.map { section in
                let mistakes = section.entries.flatMap { progress(for: $0.lesson.id).attempts.last?.feedback ?? [] }
                    .filter { !$0.correct }.prefix(3).map { String($0.explanation.prefix(150)) }
                return "\(section.entries.first?.section.title ?? section.id): \(section.entries.map(\.lesson.title).joined(separator: ", ")). \(mistakes.joined(separator: " "))"
            }.joined(separator: "\n")
            let source = draft.mode == .checkpoint
                ? snapshot.sections.first { $0.id == draft.sourceSectionID }?.entries.first : nil
            if draft.mode == .checkpoint, source == nil { throw CourseError.invalid("Раздел для контрольной не найден.") }
            generationPhase = 1
            for topic in draft.selected where !draft.prepared.contains(where: { $0.topicID == topic.id }) {
                let generated = try await PlanGenerator.generate(
                    topic, draft: draft, level: level, minutes: dailyGoalMinutes,
                    diagnosis: diagnosis, course: String(course.prefix(12_000)), source: source,
                    executablePath: executablePath
                )
                try Task.checkCancellation()
                draft.prepared.append(generated)
                guard updatePlanning({ $0.draft = draft }) else { return }
            }
            generationPhase = 2
            await Task.yield()
            try Task.checkCancellation()
            var state = planning
            if draft.mode == .first || draft.mode == .extend {
                for section in draft.prepared {
                    guard let anchor = section.entries.first,
                          let topic = draft.selected.first(where: { $0.id == section.topicID }) else { continue }
                    let id = "\(anchor.module.id)/\(anchor.section.id)"
                    let described = StudyTopic(id: topic.id, title: topic.title,
                                               goal: anchor.section.theory.trimmed.isEmpty ? topic.goal : anchor.section.theory)
                    state.route.append(PlannedSection(id: id, topic: described, level: level))
                }
            }
            if draft.mode == .first { state.firstPlanCreated = true }
            let sections = draft.prepared
            draft.stage = .ready
            draft.prepared = []
            state.draft = draft
            try store.commitPlan(sections, state: state, requestID: draft.id)
            planning = state
            snapshot = try store.snapshot()
        } catch is CancellationError {
            return
        } catch {
            generationError = error.localizedDescription
        }
    }

    func progress(for id: String) -> Progress {
        snapshot.progress[id] ?? Progress()
    }

    @discardableResult
    func updateLearningSetup(_ change: (inout LearningSetup) -> Void) -> Bool {
        do {
            guard let store else { throw CourseError.storage("Учебная база ещё не открылась.") }
            var setup = learningSetup ?? LearningSetup()
            change(&setup)
            try store.saveLearningSetup(setup)
            learningSetup = setup
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func setAnswer(_ answer: String, exerciseID: String, in lesson: Lesson) {
        guard !checking.contains(lesson.id), !progress(for: lesson.id).finished,
              progress(for: lesson.id).practice?.checks.contains(where: { $0.feedback.id == exerciseID }) != true else { return }
        if !answer.trimmed.isEmpty { startStudy(lesson) }
        update(lesson.id) { progress in
            if progress.practice == nil && !answer.trimmed.isEmpty {
                progress.practice = PracticeDraft(
                    stepID: "exercise/\(exerciseID)", startedAt: activeStudy?.start ?? .now,
                    storyVersion: lesson.story?.version
                )
            }
            progress.draft[exerciseID] = answer
        }
    }

    func startStudy(_ lesson: Lesson) {
        guard store != nil, !checking.contains(lesson.id), !progress(for: lesson.id).finished,
              activeStudy?.key != lesson.id else { return }
        let now = Date.now
        beginStudy(lessonID: lesson.id, activityID: nil, at: now)
        if let minutes = lesson.timeLimitMinutes, progress(for: lesson.id).timerEndsAt == nil {
            update(lesson.id) { $0.timerEndsAt = now.addingTimeInterval(TimeInterval(minutes * 60)) }
        }
    }

    func startVocabulary(in section: StudySection, activityID: String) {
        guard store != nil, activeStudy?.key != activityID, let anchor = section.entries.first else { return }
        beginStudy(lessonID: anchor.lesson.id, activityID: activityID, at: .now)
    }

    private func beginStudy(lessonID: String, activityID: String?, at now: Date) {
        pauseStudy(at: now)
        activeStudy = StudyRun(lessonID: lessonID, start: now, activityID: activityID)
        lastStudyCheckpoint = now
    }

    func pauseStudy(activityID: String? = nil, at now: Date = .now) {
        guard let run = activeStudy, activityID == nil || run.key == activityID else { return }
        activeStudy = nil
        lastStudyCheckpoint = nil
        pendingStudy.append(run.interval(through: now))
        do {
            if let store { try updateStudyTime(in: store, now: now) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func prepareLessonVocabulary(_ entry: CourseEntry) {
        let lesson = entry.lesson
        let current = progress(for: lesson.id)
        guard !lesson.isCheckpoint, lesson.story == nil, lesson.exercises.count < 30,
              current.vocabularyCards == nil, !current.finished, current.practice == nil,
              current.draft.isEmpty, current.timerEndsAt == nil,
              let items = snapshot.vocabulary["\(entry.module.id)/\(entry.section.id)"], !items.isEmpty else { return }
        let cards = vocabularyRoundCards(items, previous: current.attempts.last?.vocabularyCards ?? [], retry: [])
        update(lesson.id) { $0.vocabularyCards = cards }
    }

    func reviewVocabulary(_ id: String, correct: Bool, in section: StudySection, updateSchedule: Bool = true,
                          countCheck: Bool = true, now: Date = .now) -> Bool {
        guard let anchor = section.entries.first else { return false }
        do {
            try saveVocabularyResults(updateSchedule ? [id: correct] : [:], entry: anchor, now: now,
                                      extraCheck: countCheck, progress: nil)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func saveVocabularyResults(_ results: [String: Bool], entry: CourseEntry, now: Date,
                                       extraCheck: Bool, progress: Progress?) throws {
        let sectionID = "\(entry.module.id)/\(entry.section.id)"
        guard let store, var items = snapshot.vocabulary[sectionID] else {
            throw CourseError.storage("Не удалось сохранить результат тренировки слов.")
        }
        var reviews: [String: VocabularyReview] = [:]
        for index in items.indices {
            let item = items[index]
            guard let correct = results[item.id], !correct || item.isDue(at: now) else { continue }
            let review = VocabularyReview.next(after: item.review, correct: correct, now: now)
            items[index].review = review
            reviews[item.id] = review
        }
        let day = Calendar.current.startOfDay(for: now)
        let alreadyPracticed = snapshot.practiceDays().contains(day)
        try store.saveVocabularyReviews(reviews, moduleID: entry.module.id, sectionID: entry.section.id,
                                        practiceDay: day, extraCheck: extraCheck, progress: progress, lessonID: entry.lesson.id)
        if let progress { snapshot.progress[entry.lesson.id] = progress }
        snapshot.vocabulary[sectionID] = items
        snapshot.vocabularyPracticeDays.insert(day)
        if extraCheck { snapshot.extraVocabularyChecks[day, default: 0] += 1 }
        if !alreadyPracticed { pendingStreakDay = day }
    }

    func retry(_ lesson: Lesson) {
        update(lesson.id) { progress in
            progress.draft = [:]
            progress.timerEndsAt = nil
            progress.vocabularyCards = nil
            progress.isRetrying = true
            progress.practice = nil
        }
    }

    func acknowledgeStreakDay() {
        pendingStreakDay = nil
    }

    func movePractice(_ lesson: Lesson, to step: PracticeStep) {
        guard !checking.contains(lesson.id), !progress(for: lesson.id).finished else { return }
        startStudy(lesson)
        update(lesson.id) { progress in
            var practice = progress.practice ?? PracticeDraft(stepID: step.id, storyVersion: lesson.story?.version)
            practice.stepID = step.id
            progress.practice = practice
        }
    }

    func setPracticeWords(_ indices: [Int], exercise: Exercise, in lesson: Lesson) {
        let current = progress(for: lesson.id)
        guard let words = exercise.words, indices.allSatisfy(words.indices.contains),
              Set(indices).count == indices.count, !current.finished, !checking.contains(lesson.id),
              current.practice?.checks.contains(where: { $0.feedback.id == exercise.id }) != true else { return }
        startStudy(lesson)
        let saved = update(lesson.id) { progress in
            var practice = progress.practice ?? PracticeDraft(
                stepID: "exercise/\(exercise.id)", storyVersion: lesson.story?.version
            )
            practice.wordTiles[exercise.id] = indices
            progress.practice = practice
            progress.draft[exercise.id] = indices.map { words[$0] }.joined(separator: " ")
        }
        let previousCount = current.practice?.wordTiles[exercise.id]?.count ?? 0
        if saved, exercise.kind == .translationTiles, indices.count != previousCount {
            playSound(indices.count > previousCount ? .wordPick : .wordReturn)
        }
    }

    func selectPair(_ pick: TranslationPairSelection.Pick, exercise: Exercise, in lesson: Lesson) {
        let current = progress(for: lesson.id)
        guard let pairs = exercise.pairs, pairs.indices.contains(pick.index), !current.finished,
              !checking.contains(lesson.id),
              current.practice?.checks.contains(where: { $0.feedback.id == exercise.id }) != true else { return }
        startStudy(lesson)
        var selection = current.practice?.pairSelections?[exercise.id] ?? TranslationPairSelection()
        selection.select(pick)
        let saved = update(lesson.id) { progress in
            var practice = progress.practice ?? PracticeDraft(stepID: "exercise/\(exercise.id)", storyVersion: lesson.story?.version)
            var selections = practice.pairSelections ?? [:]
            selections[exercise.id] = selection
            practice.pairSelections = selections
            progress.practice = practice
            progress.draft[exercise.id] = selection.answer(for: pairs)
        }
        if saved, !lesson.isCheckpoint, let partner = selection.partner(of: pick) {
            playSound(partner == pick.index ? .pairCorrect : .pairIncorrect)
        }
    }

    func checkExercise(_ exercise: Exercise, in lesson: Lesson, executablePath: String) async {
        let current = progress(for: lesson.id)
        guard !lesson.isCheckpoint, !current.finished, !checking.contains(lesson.id),
              current.practice?.checks.contains(where: { $0.feedback.id == exercise.id }) != true,
              current.canSubmit(exercise), let answer = current.draft[exercise.id] else { return }
        checking.insert(lesson.id)
        defer { checking.remove(lesson.id) }
        do {
            let feedback: Feedback
            if exercise.kind.needsCodex {
                pauseStudy(activityID: lesson.id)
                let reviews = try await CodexReviewer.review(
                    lesson: lesson, questions: [.init(id: exercise.id, prompt: exercise.prompt,
                                                      rubric: exercise.rubric ?? "", answer: answer)],
                    executablePath: executablePath
                )
                guard let review = reviews.first else { return }
                feedback = review
            } else {
                feedback = exercise.grade(answer)
            }
            try Task.checkCancellation()
            var updated = progress(for: lesson.id)
            let now = Date.now
            let day = Calendar.current.startOfDay(for: now)
            let alreadyPracticed = snapshot.practiceDays().contains(day)
            var practice = updated.practice ?? PracticeDraft(
                stepID: "exercise/\(exercise.id)", startedAt: activeStudy?.start ?? now,
                storyVersion: lesson.story?.version
            )
            let milestone = updated.attempts.isEmpty && feedback.correct && snapshot.correctAnswerStreak == 9
                && !snapshot.firstChecks.contains {
                    $0.reachedMilestone == true && Calendar.current.isDate($0.date, inSameDayAs: now)
                }
            practice.checks.append(ExerciseCheck(feedback: feedback, date: now, reachedMilestone: milestone))
            updated.practice = practice
            if let ids = exercise.vocabularyIDs, let entry = snapshot.entries.first(where: { $0.lesson.id == lesson.id }) {
                let pairs = updated.practice?.pairSelections?[exercise.id]
                var results: [String: Bool] = [:]
                for (index, id) in ids.enumerated() {
                    results[id] = exercise.kind == .translationPairs ? pairs?.links[index] == index : feedback.correct
                }
                try saveVocabularyResults(results, entry: entry, now: now, extraCheck: false, progress: updated)
            } else {
                try save(updated, for: lesson.id)
            }
            playSound(.answer(correct: feedback.correct, translationCard: exercise.kind == .translationCard))
            if !alreadyPracticed { pendingStreakDay = day }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    func finishPractice(_ lesson: Lesson) {
        let current = progress(for: lesson.id)
        guard !current.finished, !checking.contains(lesson.id), let practice = current.practice else { return }
        let byID = Dictionary(uniqueKeysWithValues: practice.checks.map { ($0.feedback.id, $0.feedback) })
        let feedback = lesson.exercises.compactMap { byID[$0.id] }
        guard feedback.count == lesson.exercises.count else { return }
        do {
            try commitAttempt(lesson, feedback: feedback, checks: practice.checks)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func check(_ lesson: Lesson, executablePath: String) async {
        let current = progress(for: lesson.id)
        guard !current.finished, !checking.contains(lesson.id),
              lesson.exercises.allSatisfy(current.canSubmit) else { return }
        pauseStudy(activityID: lesson.id)
        checking.insert(lesson.id)
        defer { checking.remove(lesson.id) }
        do {
            let written: [CodexReviewer.Question] = lesson.exercises.filter { $0.kind.needsCodex }.map {
                .init(id: $0.id, prompt: $0.prompt, rubric: $0.rubric ?? "", answer: current.draft[$0.id] ?? "")
            }
            let reviews: [Feedback] = if written.isEmpty {
                []
            } else {
                try await CodexReviewer.review(lesson: lesson, questions: written, executablePath: executablePath)
            }
            let byID = Dictionary(uniqueKeysWithValues: reviews.map { ($0.id, $0) })
            let feedback = lesson.exercises.map { exercise in
                byID[exercise.id] ?? exercise.grade(current.draft[exercise.id] ?? "")
            }
            try Task.checkCancellation()
            try commitAttempt(lesson, feedback: feedback, checks: nil)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func commitAttempt(_ lesson: Lesson, feedback: [Feedback], checks: [ExerciseCheck]?) throws {
        var current = progress(for: lesson.id)
        guard !current.finished, let store else { return }
        let now = Date.now
        let day = Calendar.current.startOfDay(for: now)
        let alreadyPracticed = snapshot.practiceDays().contains(day)
        let start = current.practice?.startedAt ?? current.attempts.last?.date ?? .distantPast
        pauseStudy(activityID: lesson.id, at: now)
        let seconds = try store.studySeconds(for: lesson.id, since: start)
        var attempt = Attempt(date: now, answers: current.draft, feedback: feedback, checks: checks, studySeconds: seconds)
        if lesson.isCheckpoint && !lesson.passed(attempt) {
            attempt.celebration = .checkpointFailed
        } else if checks?.contains(where: { $0.reachedMilestone == true }) == true {
            attempt.celebration = .streak
        } else if current.attempts.isEmpty && feedback.allSatisfy(\.correct) {
            attempt.celebration = .perfect
        } else {
            attempt.celebration = lesson.kind == .story ? .story : .completed
        }
        attempt.vocabularyCards = current.vocabularyCards
        current.attempts.append(attempt)
        current.practice = nil
        current.isRetrying = false
        current.timerEndsAt = nil
        current.reminderAt = nil
        try save(current, for: lesson.id)
        if lesson.isCheckpoint { playSound(.answer(correct: feedback.allSatisfy(\.correct))) }
        if !alreadyPracticed { pendingStreakDay = day }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [lesson.id])
    }

    func setDueDate(_ date: Date?, for lesson: Lesson) {
        update(lesson.id) { $0.dueAt = date }
    }

    func configureDailyReminder(enabled: Bool, minutes: Int, goalMinutes: Int? = nil) async {
        guard !configuringDailyReminder, (0..<1440).contains(minutes) else { return }
        configuringDailyReminder = true
        defer { configuringDailyReminder = false }
        dailyReminderEnabled = enabled
        dailyReminderMinutes = minutes
        UserDefaults.standard.set(enabled, forKey: "dailyReminderEnabled")
        UserDefaults.standard.set(minutes, forKey: "dailyReminderMinutes")

        let center = UNUserNotificationCenter.current()
        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderID])
            dailyReminderStatus = .off
            return
        }
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                dailyReminderStatus = .needsPermission
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Время для английского"
            content.body = "Дневная цель — \(goalMinutes ?? dailyGoalMinutes) минут. Открой план и продолжи с ближайшего задания."
            content.userInfo = ["openStudyPlan": true]
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60), repeats: true
            )
            try await center.add(UNNotificationRequest(identifier: Self.dailyReminderID, content: content, trigger: trigger))
            dailyReminderStatus = .scheduled
        } catch {
            dailyReminderStatus = .failed
        }
    }

    func setReminder(_ date: Date, for lesson: Lesson) async {
        let center = UNUserNotificationCenter.current()
        do {
            guard date > Date() else { throw CourseError.invalid("Выбери время напоминания в будущем.") }
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw CourseError.invalid("Разреши уведомления для English Practice в системных настройках macOS.")
            }
            var current = progress(for: lesson.id)
            guard !current.finished, !checking.contains(lesson.id) else { return }
            guard date > Date() else { throw CourseError.invalid("Выбери время напоминания в будущем.") }
            try await center.add(reminderRequest(for: lesson, at: date))
            current = progress(for: lesson.id)
            guard !current.finished else {
                center.removePendingNotificationRequests(withIdentifiers: [lesson.id])
                return
            }
            let previous = current.reminderAt
            current.reminderAt = date
            do {
                try save(current, for: lesson.id)
            } catch {
                if let previous, previous > Date() {
                    try? await center.add(reminderRequest(for: lesson, at: previous))
                } else {
                    center.removePendingNotificationRequests(withIdentifiers: [lesson.id])
                }
                throw error
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clearReminder(for lesson: Lesson) {
        do {
            var current = progress(for: lesson.id)
            current.reminderAt = nil
            try save(current, for: lesson.id)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [lesson.id])
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reminderRequest(for lesson: Lesson, at date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Домашняя работа ждёт"
        content.body = lesson.title
        content.userInfo = ["lessonId": lesson.id]
        content.sound = .default
        return UNNotificationRequest(
            identifier: lesson.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        )
    }

    @discardableResult
    private func update(_ lessonID: String, change: (inout Progress) -> Void) -> Bool {
        do {
            var current = progress(for: lessonID)
            change(&current)
            try save(current, for: lessonID)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func updateStudyTime(in store: CourseStore, now: Date) throws {
        var wroteTime = !pendingStudy.isEmpty
        while let interval = pendingStudy.first {
            try store.saveStudy(interval)
            pendingStudy.removeFirst()
        }
        if let run = activeStudy, let lastStudyCheckpoint,
           now.timeIntervalSince(lastStudyCheckpoint) >= 10 {
            try store.saveStudy(run.interval(through: now))
            self.lastStudyCheckpoint = now
            wroteTime = true
        }
        if let day = Calendar.current.dateInterval(of: .day, for: now), wroteTime || day.start != studyDay {
            todayStudySeconds = try store.studySeconds(in: day)
            studyDay = day.start
        }
    }

    private func save(_ progress: Progress, for lessonID: String) throws {
        guard let store else { throw CourseError.storage("Учебная база ещё не открылась.") }
        try store.save(progress, for: lessonID)
        snapshot.progress[lessonID] = progress
    }
}
