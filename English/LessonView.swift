import SwiftUI

struct LessonView: View {
    let entry: CourseEntry
    let model: StudyModel
    let back: () -> Void
    var acceptLevel: (() -> Void)?

    @AppStorage("codexPath") private var codexPath = CodexReviewer.detectedPath
    @State private var speech = PracticeSpeech()
    @State private var showsVocabulary = false
    @State private var showsSchedule = false
    @State private var history: Attempt?
    @State private var reviewTask: Task<Void, Never>?

    private var lesson: Lesson { entry.lesson.includingVocabulary(progress.vocabularyCards ?? []) }
    private var vocabularySection: StudySection? {
        let id = "\(entry.module.id)/\(entry.section.id)"
        guard model.snapshot.vocabulary[id]?.isEmpty == false else { return nil }
        return model.snapshot.sections.first { $0.id == id }
    }
    private var progress: Progress { model.progress(for: entry.lesson.id) }
    private var steps: [PracticeStep] { lesson.practiceSteps }
    private var index: Int {
        if let saved = steps.firstIndex(where: { $0.id == progress.practice?.stepID }) { return saved }
        if steps.count > 1, case .line(let narrator, let firstPart) = steps[0], narrator.speaker == nil,
           case .line(_, let secondPart) = steps[1], firstPart == secondPart { return 1 }
        return 0
    }
    private var isChecking: Bool { model.checking.contains(lesson.id) }

    var body: some View {
        Group {
            if progress.finished, let attempt = progress.attempts.last {
                LessonResultView(entry: entry, attempt: attempt, firstAttempt: progress.attempts.first ?? attempt,
                                 back: back, retry: { model.retry(lesson) }, acceptLevel: acceptLevel)
            } else if steps.indices.contains(index) {
                let step = steps[index]
                StudyWorkspace {
                    VStack(alignment: .leading, spacing: 15) {
                        switch step {
                        case .line(_, let part):
                            reading(part: part)
                        case .exercise(let exercise, let number):
                            exercisePage(exercise, number: number)
                        }
                    }
                } footer: {
                    HStack {
                        Button("Сохранить и выйти", action: back).buttonStyle(StudySecondaryStyle())
                        Spacer(minLength: 16)
                        action(for: step)
                    }
                }
            } else {
                ContentUnavailableView("В уроке пока нет заданий", systemImage: "book")
            }
        }
        .navigationTitle(lesson.kind == .story ? lesson.title : entry.section.title)
        .toolbar {
            ToolbarItem(placement: .navigation) { StudyBackButton(action: back) }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if lesson.kind != .story { StudyStreaks(model: model, compact: true) }
                    Text(model.levelBadge).planPill()
                    lessonMenu
                }
            }
        }
        .sheet(item: $history) { attempt in
            StudyPage {
                Text("Разбор попытки").font(PlanStyle.title)
                ForEach(entry.lesson.includingVocabulary(attempt.vocabularyCards ?? []).exercises) { exercise in
                    if let feedback = attempt.feedback.first(where: { $0.id == exercise.id }) {
                        VStack(alignment: .leading, spacing: 10) {
                            MarkdownText(exercise.prompt)
                            Text(attempt.answers[exercise.id] ?? "").font(PlanStyle.answer)
                            feedbackCard(feedback, audio: exercise.speechText)
                        }
                        .planCard()
                    }
                }
                Button("Закрыть") { history = nil }.buttonStyle(StudySecondaryStyle())
            }
            .frame(minWidth: 590, minHeight: 460)
        }
        .onChange(of: progress.finished, initial: true) { _, finished in
            if !finished { model.prepareLessonVocabulary(entry) }
        }
        .sheet(isPresented: $showsVocabulary) {
            if let section = vocabularySection {
                VocabularyView(section: section, model: model) { showsVocabulary = false }
                    .frame(minWidth: 620, minHeight: 500)
            }
        }
        .onDisappear {
            reviewTask?.cancel()
            speech.stop()
            model.pauseStudy(activityID: lesson.id)
        }
    }

    private var lessonMenu: some View {
        Menu {
            if !progress.finished {
                if model.activeStudy?.key == lesson.id {
                    Button("Пауза") { speech.stop(); model.pauseStudy(activityID: lesson.id) }
                } else {
                    Button("Начать занятие") { model.startStudy(lesson) }
                }
            }
            if !lesson.isCheckpoint, vocabularySection != nil {
                Button("Повторить слова раздела") {
                    speech.stop()
                    model.pauseStudy(activityID: lesson.id)
                    showsVocabulary = true
                }
            }
            if lesson.kind == .homework {
                Button("Срок и напоминание…") { showsSchedule = true }
            }
            if progress.finished { Button("Повторить") { model.retry(lesson) } }
            ForEach(progress.attempts.reversed()) { attempt in
                Button("Попытка · \(attempt.date.formatted(.dateTime.day().month().hour().minute()))") {
                    history = attempt
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle").accessibilityLabel("Действия занятия")
        }
        .disabled(isChecking)
        .popover(isPresented: $showsSchedule) { ScheduleView(lesson: lesson, model: model) }
    }

    private func meter(_ title: String, detail: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(PlanStyle.label).foregroundStyle(PlanStyle.onSoft)
                Spacer()
                Text(detail).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            }
            PlanProgressBar(value: value, height: 7)
        }
    }

    private func exercisePage(_ exercise: Exercise, number: Int) -> some View {
        let feedback = progress.practice?.checks.first { $0.feedback.id == exercise.id }?.feedback
        let answer = progress.draft[exercise.id] ?? ""
        return VStack(alignment: .leading, spacing: 14) {
            meter("\(lesson.kind == .story ? "ВОПРОС" : "ЗАДАНИЕ") \(number) ИЗ \(lesson.exercises.count)",
                  detail: exercise.speechText == nil ? (exercise.topic ?? exercise.title) : "Аудирование",
                  value: Double(number) / Double(lesson.exercises.count))
            Text(lesson.kind == .story && exercise.kind == .choice ? exercise.prompt : exerciseHeading(exercise))
                .font(PlanStyle.title).accessibilityAddTraits(.isHeader)
            if let story = lesson.story, exercise.speechText == nil, exercise.kind != .wordOrder {
                if let scene = story.scenes.first(where: { $0.exercises.contains(exercise.id) }) {
                    ForEach(Array(scene.lines.suffix(2))) { storyLine($0) }
                }
                DisclosureGroup("Прочитанные реплики") {
                    VStack(alignment: .leading, spacing: 10) { revealedLines }
                        .padding(.top, 8)
                }
                .font(PlanStyle.caption)
                .accessibilityIdentifier("story-context-\(story.version)")
            }
            if !lesson.isCheckpoint && number == 1 {
                lessonNotes
            }
            if lesson.isCheckpoint, number == 1, let percent = lesson.passingPercent {
                Text("Для зачёта нужно \(percent)% верных ответов. Разбор откроется после сдачи.")
                    .font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            }
            if let audio = exercise.speechText {
                audioCard(audio)
                    .onDisappear { speech.stop() }
                    .id(exercise.id)
            }
            if (exercise.speechText != nil && lesson.kind != .story) || exercise.kind == .wordOrder {
                MarkdownText(exercise.prompt).font(exercise.kind == .wordOrder ? PlanStyle.prompt : PlanStyle.body)
            } else if exercise.kind == .translationTiles || exercise.kind == .translationChoice {
                HStack(spacing: 16) {
                    StudyGraphic.practiceDialogue.frame(width: 44, height: 44)
                        .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 14))
                    MarkdownText(exercise.prompt, bodyFont: PlanStyle.prompt)
                }
                .frame(minHeight: 64, alignment: .leading)
                .planCard(padding: 16)
            } else if exercise.kind != .translationCard, exercise.kind != .translationPairs,
                      lesson.kind != .story || exercise.kind != .choice {
                HStack(spacing: 16) {
                    if exercise.kind == .dialogue {
                        StudyGraphic.practiceDialogue.frame(width: 44, height: 44)
                            .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 14))
                    }
                    MarkdownText(exercise.prompt).font(PlanStyle.prompt)
                }
                .frame(minHeight: 44, alignment: .leading)
                .planCard(padding: 24)
            }
            response(exercise, answer: answer, feedback: feedback)
                .disabled(isChecking || feedback != nil)
            if let feedback {
                feedbackCard(feedback, audio: exercise.speechText)
                if let ids = exercise.vocabularyIDs {
                    let examples = ids.compactMap { id in progress.vocabularyCards?.first { $0.id == id }?.example }
                    Button("Прослушать пример", systemImage: "speaker.wave.2") {
                        model.startStudy(lesson)
                        speech.play(examples.joined(separator: " ")) { model.error = $0 }
                    }
                    .buttonStyle(StudySecondaryStyle())
                }
            } else if exercise.kind.needsCodex {
                Text(isChecking ? "Codex проверяет ответ…" : "Свободный ответ проверит подключённый Codex.")
                    .font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            }
        }
        .background(alignment: .topTrailing) {
            if let end = progress.timerEndsAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = Int(max(0, end.timeIntervalSince(context.date)))
                    Text(seconds == 0 ? "Время вышло" : "\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                        .font(PlanStyle.caption.monospacedDigit())
                        .padding(.trailing, 3)
                        .offset(y: -20)
                }
            }
        }
    }

    private var lessonNotes: some View {
        Group {
            if !lesson.theory.trimmed.isEmpty || !entry.module.theory.trimmed.isEmpty || !entry.section.theory.trimmed.isEmpty {
                DisclosureGroup("Теория и примеры") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach([entry.module.theory, entry.section.theory, lesson.theory].indices, id: \.self) { i in
                            let note = [entry.module.theory, entry.section.theory, lesson.theory][i]
                            if !note.trimmed.isEmpty { MarkdownText(note) }
                        }
                    }
                    .padding(.top, 10)
                }
                .font(PlanStyle.caption)
            }
        }
    }

    private func exerciseHeading(_ exercise: Exercise) -> String {
        if exercise.speechText != nil { return "Послушай и выбери ответ" }
        switch exercise.kind {
        case .translationPairs: return exercise.prompt
        case .choice: return "Выбери правильный вариант"
        case .dialogue: return "Ответь собеседнику"
        default: return exercise.title
        }
    }

    private func audioCard(_ text: String) -> some View {
        Button {
            model.startStudy(lesson)
            speech.play(text) { model.error = $0 }
        } label: {
            HStack(spacing: 16) {
                StudyGraphic.practiceAudio.frame(width: 52, height: 52)
                    .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Прослушать фразу").font(PlanStyle.button)
                    Text("Фразу можно включить ещё раз.").font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                }
                Spacer()
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !speech.isPlaying)) { _ in
                    SpeechProgressWaveform(progress: speech.playbackProgress)
                }
                .accessibilityHidden(true)
            }
            .planCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func response(_ exercise: Exercise, answer: String, feedback: Feedback?) -> some View {
        switch exercise.kind {
        case .choice, .translationChoice:
            VStack(spacing: exercise.kind == .translationChoice ? 9 : 14) {
                ForEach(exercise.options ?? [], id: \.self) { option in
                    let accepted = feedback != nil && exercise.acceptedAnswers?.contains {
                        $0.normalizedAnswer == option.normalizedAnswer
                    } == true
                    let wrong = feedback?.correct == false && answer == option
                    StudyChoice(selected: answer == option, result: accepted ? true : (wrong ? false : nil)) {
                        model.setAnswer(option, exerciseID: exercise.id, in: lesson)
                    } label: {
                        Text(option).font(PlanStyle.answer)
                    }
                }
            }
        case .wordOrder:
            wordTiles(exercise)
        case .translationTiles:
            let words = exercise.words ?? []
            let selected = (progress.practice?.wordTiles[exercise.id] ?? []).filter(words.indices.contains)
            TranslationTilesView(words: words, selected: selected, feedback: feedback) {
                model.setPracticeWords($0, exercise: exercise, in: lesson)
            }
            .id(exercise.id)
        case .translationPairs:
            TranslationPairsView(pairs: exercise.pairs ?? [],
                                 selection: progress.practice?.pairSelections?[exercise.id] ?? TranslationPairSelection(),
                                 checked: feedback != nil) {
                model.selectPair($0, exercise: exercise, in: lesson)
            }
        case .translationCard:
            TranslationCardView(exercise: exercise, answer: answerBinding(for: exercise), feedback: feedback,
                                check: lesson.isCheckpoint ? nil : { checkAnswer(exercise) })
        case .gap, .correction, .written, .dialogue:
            let binding = answerBinding(for: exercise)
            let shape = RoundedRectangle(cornerRadius: 12)
            if exercise.kind.needsCodex {
                Text("Ответь по-английски.").font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
                TextEditor(text: binding).scrollContentBackground(.hidden)
                    .font(PlanStyle.answer).padding(11).frame(minHeight: 140)
                    .background(PlanStyle.card, in: shape)
                    .overlay { shape.strokeBorder(PlanStyle.action, lineWidth: 2).allowsHitTesting(false) }
                    .accessibilityLabel("Напиши ответ здесь")
            } else {
                TextField("Твой ответ", text: binding).textFieldStyle(.plain)
                    .font(PlanStyle.answer).padding(13)
                    .background(PlanStyle.card, in: shape)
                    .overlay { shape.strokeBorder(PlanStyle.connector).allowsHitTesting(false) }
            }
        }
    }

    private func answerBinding(for exercise: Exercise) -> Binding<String> {
        Binding(get: { model.progress(for: lesson.id).draft[exercise.id] ?? "" }, set: {
            model.setAnswer($0, exerciseID: exercise.id, in: lesson)
        })
    }

    private func checkAnswer(_ exercise: Exercise) {
        reviewTask = Task { await model.checkExercise(exercise, in: lesson, executablePath: codexPath.trimmed) }
    }

    private func wordTiles(_ exercise: Exercise) -> some View {
        let words = exercise.words ?? []
        let selected = (progress.practice?.wordTiles[exercise.id] ?? []).filter(words.indices.contains)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("ТВОЙ ОТВЕТ").font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                if selected.isEmpty {
                    Text("Нажми на слова в нужном порядке").font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
                } else {
                    tiles(selected, words: words) { value in
                        model.setPracticeWords(selected.filter { $0 != value }, exercise: exercise, in: lesson)
                    }
                }
            }
            .frame(minHeight: 72, alignment: .leading)
            .planCard(radius: 16)
            Text("СЛОВА").font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            tiles(words.indices.filter { !selected.contains($0) }, words: words) { value in
                model.setPracticeWords(selected + [value], exercise: exercise, in: lesson)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(PlanStyle.subtle, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func tiles(_ ids: [Int], words: [String], action: @escaping (Int) -> Void) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    Button(words[id]) { action(id) }.buttonStyle(StudySecondaryStyle())
                }
            }
        }
    }

    private func reading(part: Int) -> some View {
        let scene = lesson.story?.scenes[part - 1]
        let lastInScene = index == steps.count - 1 || !isLine(steps[index + 1])
        return VStack(alignment: .leading, spacing: 14) {
            meter("ЧАСТЬ \(part) ИЗ \(lesson.story?.scenes.count ?? 1)", detail: "История",
                  value: Double(index + 1) / Double(steps.count))
            Text(scene?.title ?? lesson.title).font(PlanStyle.title).accessibilityAddTraits(.isHeader)
            if part == 1 && lesson.exercises.count < 20 { Text("РАЗМИНКА").planPill() }
            Text(scene?.instruction ?? (lastInScene ? "Дочитай диалог и переходи дальше."
                 : "Читай диалог. Новая реплика появится по кнопке внизу."))
                .font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
            ForEach(Array(steps.prefix(index + 1))) { step in
                if case .line(let line, let linePart) = step, linePart == part { storyLine(line) }
            }
            if part > 1 {
                DisclosureGroup("Предыдущие реплики") {
                    ForEach(Array(steps.prefix(index))) { step in
                        if case .line(let line, let linePart) = step, linePart < part { storyLine(line) }
                    }
                }
                .font(PlanStyle.caption)
            }
        }
    }

    private var revealedLines: some View {
        ForEach(Array(steps.prefix(index + 1))) { step in
            if case .line(let line, _) = step { storyLine(line) }
        }
    }

    private func storyLine(_ line: StoryScript.Scene.Line) -> some View {
                let speakers = lesson.story?.scenes.flatMap(\.lines).compactMap(\.speaker) ?? []
                let palette = [PlanStyle.soft, PlanStyle.successBackground, PlanStyle.rewardBackground]
                let ordered = speakers.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                let color = line.speaker.flatMap { ordered.firstIndex(of: $0) }.map { palette[$0 % palette.count] }
                return HStack(spacing: 14) {
                    if let speaker = line.speaker {
                        Text(String(speaker.prefix(1))).font(PlanStyle.label)
                            .frame(width: 42, height: 42).background(color ?? PlanStyle.soft, in: Circle())
                    } else {
                        StudyGraphic.storyNarrator.frame(width: 36, height: 36).background(PlanStyle.card, in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(line.speaker ?? "АВТОР").font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                        Text(line.text).font(PlanStyle.answer).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(color ?? PlanStyle.subtle, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(line.speaker == nil ? 8 : 0)
                .background(line.speaker == nil ? PlanStyle.subtle : .clear, in: RoundedRectangle(cornerRadius: 16))
    }

    private func feedbackCard(_ feedback: Feedback, audio: String?) -> some View {
        let color = feedback.correct ? PlanStyle.success : Color(.setupErrorText)
        return HStack(alignment: .top, spacing: 14) {
            if feedback.correct { OnboardingIcon.success.frame(width: 20) }
            else { StudyGraphic.practiceInfo.frame(width: 20) }
            VStack(alignment: .leading, spacing: 7) {
                Text(feedback.correct ? "Верно!" : (feedback.suggestion.isEmpty ? "Есть что поправить" : "Правильный ответ — \(feedback.suggestion)"))
                    .font(PlanStyle.label)
                MarkdownText(feedback.explanation).font(PlanStyle.caption)
                if let audio { Text(audio).font(PlanStyle.caption).textSelection(.enabled) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(color)
        .background(feedback.correct ? PlanStyle.successBackground : Color(.setupErrorBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private func action(for step: PracticeStep) -> some View {
        let last = index == steps.count - 1
        let title: String
        let disabled: Bool
        switch step {
        case .line:
            title = last ? "Завершить историю" : isLine(steps[index + 1]) ? "Следующая реплика" : "К вопросу"
            disabled = false
        case .exercise(let exercise, _):
            let checked = progress.practice?.checks.contains { $0.feedback.id == exercise.id } == true
            if isChecking { title = "Проверяем…" }
            else if lesson.isCheckpoint { title = last ? "Сдать контрольную" : "Далее" }
            else if checked { title = last ? "К итогу" : "Продолжить" }
            else { title = exercise.speechText == nil || lesson.kind == .story ? "Проверить" : "Далее" }
            disabled = isChecking || !progress.canSubmit(exercise)
        }
        return StudyAction(title, disabled: disabled) {
            switch step {
            case .line:
                if last { model.finishPractice(lesson) } else { advance() }
            case .exercise(let exercise, _):
                if lesson.isCheckpoint {
                    if last { reviewTask = Task { await model.check(lesson, executablePath: codexPath.trimmed) } }
                    else { advance() }
                } else if progress.practice?.checks.contains(where: { $0.feedback.id == exercise.id }) == true {
                    if last { model.finishPractice(lesson) }
                    else { advance() }
                } else {
                    checkAnswer(exercise)
                }
            }
        }
    }

    private func advance() {
        guard steps.indices.contains(index + 1) else { return }
        model.movePractice(lesson, to: steps[index + 1])
    }

    private func isLine(_ step: PracticeStep) -> Bool {
        if case .line = step { return true }
        return false
    }
}

private struct SpeechProgressWaveform: View {
    let progress: Double

    private static let heights: [CGFloat] = [6, 13, 10, 22, 30, 13, 20, 11, 17, 26, 14, 10, 5]

    var body: some View {
        Color(.planTrack)
            .overlay {
                GeometryReader { geometry in
                    Color(.planFill).frame(width: geometry.size.width * progress)
                }
            }
            .mask {
                HStack(spacing: 3) {
                    ForEach(Self.heights.indices, id: \.self) { index in
                        Capsule().frame(width: 3, height: Self.heights[index])
                    }
                }
            }
            .frame(width: CGFloat(Self.heights.count * 6 - 3), height: 30)
    }
}

struct ScheduleView: View {
    let lesson: Lesson
    let model: StudyModel
    @State private var date = Date.now.addingTimeInterval(3_600)
    @State private var saving = false

    private var progress: Progress { model.progress(for: lesson.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Срок и напоминание").font(.headline)
            DatePicker("Дата и время", selection: $date)
            HStack {
                Button("Установить срок") { model.setDueDate(date, for: lesson) }
                if progress.dueAt != nil {
                    Button("Убрать срок") { model.setDueDate(nil, for: lesson) }
                }
            }
            HStack {
                Button("Напомнить") {
                    saving = true
                    Task {
                        await model.setReminder(date, for: lesson)
                        saving = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving || progress.finished)
                if progress.reminderAt != nil {
                    Button("Убрать напоминание") { model.clearReminder(for: lesson) }
                        .disabled(saving)
                }
            }
        }
        .padding()
        .onAppear { date = progress.reminderAt ?? progress.dueAt ?? date }
    }
}
