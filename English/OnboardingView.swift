import AppKit
import SwiftUI

struct OnboardingView: View {
    let model: StudyModel
    let finish: () -> Void

    @AppStorage("codexPath") private var codexPath = CodexReviewer.detectedPath
    @State private var connection = Connection.idle
    @State private var showsAgents = false
    @State private var copiedCommand = false
    @State private var operation: Operation?
    @State private var testError: String?
    @State private var unsavedResult: PlacementResult?
    @State private var speech = PracticeSpeech()
    @FocusState private var customGoalFocused: Bool
    @FocusState private var answerFocused: Bool

    private enum Connection {
        case idle, connected, failed(String)

        var connected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    private enum Operation: Hashable { case connection, reminders, grading }

    private var setup: LearningSetup { model.learningSetup ?? LearningSetup() }
    private var stage: LearningSetup.Stage { setup.stage }
    private var questionIndex: Int { PlacementTest.items.firstIndex { $0.id == setup.questionID } ?? 0 }
    private var question: PlacementTest.Item { PlacementTest.items[questionIndex] }
    private var finalQuestion: Bool { questionIndex == PlacementTest.items.count - 1 }

    var body: some View {
        HStack(spacing: 0) {
            OnboardingSidebar(stage: stage)
                .frame(width: 288)
            Rectangle().fill(PlanStyle.border).frame(width: 1)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        VStack(alignment: .leading, spacing: 16) {
                            content
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: 548)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .id(stage == .test ? question.id : stage.rawValue)

                Rectangle().fill(PlanStyle.border).frame(height: 1)
                footer
                    .frame(maxWidth: 548)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 15)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(PlanStyle.canvas)
        .foregroundStyle(PlanStyle.text)
        .task(id: operation) {
            guard let operation else { return }
            await run(operation)
        }
        .onDisappear { speech.stop() }
        .alert("English Practice", isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        )) {
            Button("ОК") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            if stage == .agent || stage == .result || operation == .grading {
                OnboardingIcon.bolt
                    .frame(width: 44, height: 44)
                    .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 14))
            } else {
                Button(action: goBack) {
                    OnboardingIcon.back
                }
                .buttonStyle(SetupOutlineButtonStyle(width: 44, height: 44, radius: 14))
                .accessibilityLabel("Назад")
                .disabled(operation != nil)
            }
            VStack(spacing: 8) {
                HStack {
                    Text("ШАГ \(stage.number) ИЗ 7")
                        .font(PlanStyle.label)
                        .foregroundStyle(PlanStyle.onSoft)
                    Spacer()
                    Text(stage.label)
                        .font(PlanStyle.caption)
                        .foregroundStyle(PlanStyle.secondary)
                }
                HStack(spacing: 5) {
                    ForEach(1...7, id: \.self) { number in
                        Capsule()
                            .fill(number <= stage.number ? Color(.planFill) : Color(.planTrack))
                            .frame(height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(.top, 3)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .agent: agentContent
        case .motivation: motivationContent
        case .level: levelContent
        case .format: formatContent
        case .goal: goalContent
        case .reminders: reminderContent
        case .testIntro: introContent
        case .test: testContent
        case .result, .complete: resultContent
        }
    }

    @ViewBuilder
    private var agentContent: some View {
        if connection.connected {
            title("Codex подключён", "Можно перейти к настройке обучения.")
        } else {
            title("Подключи AI-агента",
                  "Установи связь с Codex, чтобы получать задания и проверять письменные ответы.")
        }
        VStack(alignment: .leading, spacing: 10) {
            Text("Агент").font(PlanStyle.label)
            Button {
                showsAgents.toggle()
            } label: {
                HStack(spacing: 12) {
                    iconTile(.codex, size: 32, background: PlanStyle.soft, radius: 9)
                    Text("Codex").font(PlanStyle.button)
                    Spacer(minLength: 12)
                    if connection.connected {
                        Text("Подключён")
                            .font(PlanStyle.caption)
                            .foregroundStyle(PlanStyle.success)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(PlanStyle.successBackground, in: Capsule())
                    }
                    OnboardingIcon.down.frame(width: 24)
                }
            }
            .buttonStyle(SetupOutlineButtonStyle(height: 56, radius: 12, selected: showsAgents, control: true))
            .accessibilityLabel("Агент, Codex")
            .accessibilityValue(showsAgents ? "Список открыт" : "Список закрыт")
            .disabled(operation != nil)

            if showsAgents {
                agentMenu
                notice("Доступен Codex", "Поддержка остальных агентов появится позже.", icon: .info, tone: .brand)
            } else if operation == .connection {
                notice("Проверяем подключение", "Ищем Codex CLI и проверяем, что сервер MCP отвечает.",
                       icon: .info, tone: .brand)
            } else if connection.connected {
                notice("Связь с Codex установлена", "Сервер english-practice отвечает. Можно начинать.",
                       icon: .success, tone: .success)
            } else {
                if case .failed(let message) = connection {
                    notice("Не удалось подключиться", message, icon: .error, tone: .error)
                }
                commandCard
                if copiedCommand {
                    notice("Команда скопирована", "Вставь её в Терминал, чтобы зарегистрировать MCP.",
                           icon: .success, tone: .success)
                } else if case .idle = connection {
                    Text("В команде указан путь к открытой копии приложения.")
                        .font(PlanStyle.caption)
                        .foregroundStyle(PlanStyle.secondary)
                }
            }
        }
    }

    private var agentMenu: some View {
        VStack(spacing: 0) {
            Button {
                showsAgents = false
            } label: {
                agentRow("Codex", icon: .codexMenu, available: true)
            }
            .buttonStyle(.plain)
            Divider()
            agentRow("Claude Code", icon: .claude, available: false)
            Divider()
            agentRow("Gemini CLI", icon: .gemini, available: false)
            Divider()
            agentRow("Cursor", icon: .cursor, available: false)
        }
        .planCard(padding: 12, radius: 16)
    }

    private func agentRow(_ title: String, icon: OnboardingIcon, available: Bool) -> some View {
        HStack(spacing: 12) {
            icon.frame(width: 24)
            Text(title).font(PlanStyle.label)
            Spacer()
            if available {
                OnboardingIcon.menuCheck.frame(width: 22)
            } else {
                Text("Скоро").font(PlanStyle.caption)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(Color(.setupDisabled), in: Capsule())
            }
        }
        .padding(.horizontal, 3)
        .frame(minHeight: 47)
        .foregroundStyle(available ? PlanStyle.text : Color(.setupOnDisabled))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var commandCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                iconTile(.terminal, size: 36, background: PlanStyle.soft, radius: 12)
                Text("Подключение к Codex CLI").font(PlanStyle.label)
            }
            caption("1. Войди в Codex CLI и выполни команду в Терминале.")
            HStack(spacing: 12) {
                Text(AgentConnection.command)
                    .font(PlanStyle.caption)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    copiedCommand = NSPasteboard.general.setString(AgentConnection.command, forType: .string)
                } label: {
                    if copiedCommand { OnboardingIcon.copyCheck } else { OnboardingIcon.copy }
                }
                .buttonStyle(SetupOutlineButtonStyle(width: 44, height: 44, radius: 12))
                .accessibilityLabel(copiedCommand ? "Команда скопирована" : "Скопировать команду")
            }
            .padding(12)
            .frame(minHeight: 84)
            .background(PlanStyle.subtle, in: RoundedRectangle(cornerRadius: 12))
            caption("2. Перезапусти Codex и нажми «Проверить подключение».")
        }
        .planCard(padding: 15, radius: 20)
    }

    @ViewBuilder
    private var motivationContent: some View {
        title("Зачем ты учишь английский?", "Выбери главную причину. Она поможет подобрать темы заданий.")
        VStack(spacing: 8) {
            ForEach(LearningSetup.Motivation.allCases, id: \.self) { motivation in
                choice(motivation.rawValue, icon: motivation.icon, selected: setup.motivation == motivation,
                       height: 48) {
                    model.updateLearningSetup { $0.motivation = motivation }
                }
            }
        }
    }

    @ViewBuilder
    private var levelContent: some View {
        title("Как ты оцениваешь свой английский?",
              "Выбери самое близкое описание. В конце проверим уровень на практике.")
        VStack(spacing: 10) {
            ForEach(LearningSetup.SelfAssessment.allCases, id: \.self) { level in
                choice(level.rawValue, icon: .grid, selected: setup.selfAssessment == level) {
                    model.updateLearningSetup { $0.selfAssessment = level }
                }
            }
        }
    }

    @ViewBuilder
    private var formatContent: some View {
        title("Что тебя ждёт на занятиях?", "Будешь тренировать английский на знакомых жизненных ситуациях.")
        VStack(spacing: 12) {
            feature("Практика общения", "Слушай фразы и отвечай в коротких диалогах.",
                    icon: .formatChat, tone: .brand)
            feature("Слова в контексте", "Повторяй полезные слова и выражения по карточкам.",
                    icon: .formatBook, tone: .success)
            feature("Занятия в своём темпе", "Ставь цель на день и следи за своим прогрессом.",
                    icon: .formatTarget, tone: .reward)
        }
    }

    @ViewBuilder
    private var goalContent: some View {
        title("Какую цель поставим на день?", "Выбери, сколько минут в день будешь уделять английскому.")
        VStack(spacing: 8) {
            ForEach([5, 10, 15, 20], id: \.self) { minutes in
                let descriptions = [5: "Лёгкая", 10: "Обычная", 15: "Серьёзная", 20: "Интенсивная"]
                choice("\(minutes) минут в день", detail: descriptions[minutes], icon: .clock,
                       selected: setup.presetMinutes == minutes, height: 50) {
                    model.updateLearningSetup { $0.presetMinutes = minutes }
                }
            }
            choice("Своё значение", icon: .pencil, selected: setup.presetMinutes == nil, height: 50) {
                if model.updateLearningSetup({ $0.presetMinutes = nil }) {
                    customGoalFocused = true
                }
            }
            if setup.presetMinutes == nil {
                customGoalField
            }
        }
    }

    private var customGoalField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Минут в день").font(PlanStyle.label)
            HStack(spacing: 12) {
                TextField("Минут в день", text: Binding(
                    get: { setup.customMinutes },
                    set: { value in model.updateLearningSetup { $0.customMinutes = String(value.prefix(4)) } }
                ), prompt: Text("Например, 30").foregroundStyle(PlanStyle.secondary))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(PlanStyle.label)
                .padding(.horizontal, 12)
                .frame(width: 168, height: 44)
                .background(PlanStyle.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(customGoalFocused ? Color(.setupFocus) : PlanStyle.connector,
                                      lineWidth: customGoalFocused ? 2 : 1)
                        .allowsHitTesting(false)
                }
                .focused($customGoalFocused)
                caption("мин")
                caption("Введи целое число от 1 до 180.")
            }
        }
        .planCard(padding: 15, radius: 16)
    }

    private var reminderIsOn: Bool {
        model.dailyReminderEnabled && !model.configuringDailyReminder
            && model.dailyReminderStatus != .needsPermission && model.dailyReminderStatus != .failed
    }

    @ViewBuilder
    private var reminderContent: some View {
        let time = ReminderTime.text(for: model.dailyReminderMinutes)
        title("Напоминать о практике?",
              "Можно получать напоминание в удобное время, чтобы не пропускать занятия.")
        banner("Каждый день в \(time)", "Время можно изменить в настройках приложения.", icon: .bell, tone: .brand)
        if reminderIsOn {
            notice("Напоминания включены", "Первое уведомление придёт в \(time) по времени Mac.",
                   icon: .success, tone: .success)
        } else if model.dailyReminderStatus == .needsPermission {
            notice("Требуется разрешение", "Разреши уведомления в настройках macOS или продолжи без них.",
                   icon: .error, tone: .error)
        } else if model.dailyReminderStatus == .failed {
            notice("Напоминание не настроено", "Попробуй ещё раз или продолжи без напоминаний.",
                   icon: .error, tone: .error)
        } else {
            caption("После нажатия macOS попросит разрешить уведомления.")
        }
    }

    @ViewBuilder
    private var introContent: some View {
        title("Определим твой уровень", "Ответь на вопросы, чтобы мы могли подобрать подходящий старт в курсе.")
        VStack(spacing: 12) {
            banner("Входной тест", "\(PlacementTest.items.count) заданий · лексика, грамматика, аудирование и короткие ответы",
                   icon: .target, tone: .brand)
            HStack(alignment: .top, spacing: 16) {
                iconTile(.warningBolt, size: 40, background: PlanStyle.card, radius: 12)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Тест использует локальный Codex").font(PlanStyle.label)
                    Text("Codex проверит свободные ответы через аккаунт, в который ты вошёл в Codex CLI. Входной тест и другие запросы к агенту расходуют токены этого аккаунта.")
                        .font(PlanStyle.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(PlanStyle.reward)
            .background(PlanStyle.rewardBackground, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    @ViewBuilder
    private var testContent: some View {
        if operation == .grading {
            title("Codex проверяет ответы", "Проверяем свободные ответы и подбираем стартовый раздел.")
            banner("Ответы получены", "Оценка появится на этом экране.", icon: .spinner, tone: .brand)
        } else {
            let exercise = question.exercise
            title(questionTitle(exercise))
            VStack(alignment: .leading, spacing: 12) {
                Text("ЗАДАНИЕ \(questionIndex + 1) ИЗ \(PlacementTest.items.count)")
                    .planPill()
                PlanProgressBar(value: Double(questionIndex + 1) / Double(PlacementTest.items.count), height: 5)
                if let audio = exercise.speechText {
                    audioButton(audio)
                    Text(exercise.prompt).font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
                } else {
                    Text(exercise.prompt)
                        .font(PlanStyle.prompt)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44, alignment: .leading)
                        .planCard(padding: 22)
                }
                if let options = exercise.options {
                    ForEach(options, id: \.self) { option in
                        choice(option, selected: setup.answers[exercise.id] == option) {
                            saveAnswer(option, for: exercise.id)
                        }
                    }
                } else {
                    if exercise.kind.needsCodex {
                        Text("Напиши 1–2 предложения.").font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
                    }
                    answerField(exercise)
                }
                if let testError {
                    notice("Не удалось проверить ответы", testError, icon: .error, tone: .error)
                }
            }
        }
    }

    private func questionTitle(_ exercise: Exercise) -> String {
        if exercise.speechText != nil { return "Прослушай фразу" }
        if exercise.kind.needsCodex { return "Ответь на английском" }
        if exercise.kind == .gap { return "Заполни пропуск" }
        return "Выбери правильный вариант"
    }

    private func audioButton(_ text: String) -> some View {
        Button {
            speech.play(text) { model.error = $0 }
        } label: {
            HStack(spacing: 16) {
                iconTile(.play, size: 48, background: PlanStyle.soft, radius: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Прослушать").font(PlanStyle.button)
                    caption("Можно прослушать несколько раз")
                }
                Spacer(minLength: 0)
            }
            .planCard(padding: 16)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Прослушать")
    }

    private func answerField(_ exercise: Exercise) -> some View {
        TextEditor(text: Binding(
            get: { setup.answers[exercise.id] ?? "" },
            set: { saveAnswer(String($0.prefix(1_000)), for: exercise.id) }
        ))
        .font(PlanStyle.answer)
        .scrollContentBackground(.hidden)
        .padding(12)
        .frame(height: exercise.kind.needsCodex ? 116 : 58)
        .background(PlanStyle.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(answerFocused || setup.answers[exercise.id]?.isEmpty == false
                              ? Color(.setupFocus) : PlanStyle.connector,
                              lineWidth: answerFocused ? 2 : 1)
                .allowsHitTesting(false)
        }
        .focused($answerFocused)
        .accessibilityLabel("Ответ на задание \(questionIndex + 1)")
    }

    @ViewBuilder
    private var resultContent: some View {
        if let result = setup.result {
            let practice = result.sectionID == "present-tenses/present-contrast"
                ? "Закрепи разницу между привычками и действиями, которые происходят сейчас."
                : "Начни с простых фраз о себе и повседневных делах."
            title("Твой уровень — \(result.level)", "Рекомендуем начать с раздела «\(result.sectionTitle)».")
            VStack(spacing: 12) {
                banner("Начальный уровень", practice, icon: .rewardStar, tone: .reward)
                notice("Входной тест пройден", "Стартовый раздел подобран.", icon: .success, tone: .success)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Результаты по навыкам").font(PlanStyle.label)
                ForEach(result.scores, id: \.skill) { score in
                    HStack {
                        Text(score.skill.rawValue)
                        Spacer()
                        Text("\(score.correct) из \(score.total) · \(score.strong ? "Получается" : "Стоит повторить")")
                            .multilineTextAlignment(.trailing)
                    }
                    .font(PlanStyle.caption)
                    .foregroundStyle(score.strong ? PlanStyle.success : PlanStyle.secondary)
                }
                HStack {
                    Text("Устная речь")
                    Spacer()
                    Text("Ещё проверяем")
                }
                .font(PlanStyle.caption)
                .foregroundStyle(PlanStyle.secondary)
            }
            .planCard()
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if stage == .reminders && !reminderIsOn {
                Button("Не сейчас") {
                    if model.updateLearningSetup({
                        $0.reminderEnabled = false
                        $0.stage = .testIntro
                    }) {
                        Task { await model.configureDailyReminder(enabled: false, minutes: model.dailyReminderMinutes) }
                    }
                }
                .buttonStyle(SetupOutlineButtonStyle(width: 150, height: 52, radius: 16))
                .font(PlanStyle.button)
                .foregroundStyle(PlanStyle.onSoft)
                .disabled(operation != nil)
            } else if let footnote {
                caption(footnote)
            }
            Spacer(minLength: 0)
            Button(action: advance) {
                HStack(spacing: 12) {
                    Text(primaryTitle)
                    primaryIcon
                }
                .frame(minWidth: 172)
            }
            .buttonStyle(PlanPrimaryButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .disabled(!canAdvance)
        }
    }

    private var footnote: String? {
        switch stage {
        case .agent:
            connection.connected ? "Локальный MCP · English Practice" : "Только при первом запуске"
        case .testIntro: "Последний этап настройки"
        default: nil
        }
    }

    private var primaryTitle: String {
        if operation != nil { return "Проверяем…" }
        switch stage {
        case .agent:
            switch connection {
            case .idle: return "Проверить подключение"
            case .connected: return "Продолжить"
            case .failed: return "Повторить проверку"
            }
        case .reminders:
            return reminderIsOn ? "Продолжить" : "Включить напоминания"
        case .testIntro:
            return setup.questionID == nil ? "Начать тест" : "Продолжить тест"
        case .test:
            return finalQuestion ? "Завершить тест" : "Далее"
        case .result, .complete:
            return "Завершить настройку"
        default:
            return "Продолжить"
        }
    }

    private var primaryIcon: OnboardingIcon {
        if operation != nil { return .spinnerDisabled }
        if stage == .agent, case .failed = connection { return .refresh }
        return canAdvance ? .arrow : .arrowDisabled
    }

    private var canAdvance: Bool {
        guard operation == nil else { return false }
        switch stage {
        case .motivation: return setup.motivation != nil
        case .level: return setup.selfAssessment != nil
        case .goal: return setup.goalMinutes != nil
        case .test:
            if finalQuestion {
                return PlacementTest.items.allSatisfy { setup.answers[$0.id]?.trimmed.isEmpty == false }
            }
            return setup.answers[question.id]?.trimmed.isEmpty == false
        case .result: return setup.result != nil
        default: return true
        }
    }

    private func advance() {
        guard canAdvance else { return }
        switch stage {
        case .agent:
            if connection.connected {
                move(to: .motivation)
            } else {
                showsAgents = false
                copiedCommand = false
                operation = .connection
            }
        case .motivation:
            move(to: .level)
        case .level:
            move(to: .format)
        case .format:
            move(to: .goal)
        case .goal:
            move(to: .reminders)
        case .reminders:
            if reminderIsOn {
                move(to: .testIntro)
            } else {
                operation = .reminders
            }
        case .testIntro:
            model.updateLearningSetup {
                $0.stage = .test
                $0.questionID = $0.questionID ?? PlacementTest.items.first?.id
            }
        case .test:
            if finalQuestion {
                testError = nil
                operation = .grading
            } else {
                moveQuestion(to: questionIndex + 1)
            }
        case .result:
            if model.completeOnboarding() { finish() }
        case .complete:
            finish()
        }
    }

    private func goBack() {
        switch stage {
        case .agent, .result, .complete: break
        case .motivation: move(to: .agent)
        case .level: move(to: .motivation)
        case .format: move(to: .level)
        case .goal: move(to: .format)
        case .reminders: move(to: .goal)
        case .testIntro: move(to: .reminders)
        case .test:
            if questionIndex > 0 {
                moveQuestion(to: questionIndex - 1)
            } else {
                move(to: .testIntro)
            }
        }
    }

    private func move(to stage: LearningSetup.Stage) {
        speech.stop()
        model.updateLearningSetup { $0.stage = stage }
    }

    private func moveQuestion(to index: Int) {
        speech.stop()
        answerFocused = false
        testError = nil
        model.updateLearningSetup { $0.questionID = PlacementTest.items[index].id }
    }

    private func saveAnswer(_ answer: String, for id: String) {
        testError = nil
        unsavedResult = nil
        model.updateLearningSetup { $0.answers[id] = answer }
    }

    private func run(_ operation: Operation) async {
        defer {
            if !Task.isCancelled { self.operation = nil }
        }
        switch operation {
        case .connection:
            do {
                try await AgentConnection.verify(executablePath: codexPath)
                try Task.checkCancellation()
                connection = .connected
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                connection = .failed(error.localizedDescription)
            }
        case .reminders:
            await model.configureDailyReminder(enabled: true, minutes: model.dailyReminderMinutes, goalMinutes: setup.goalMinutes)
            guard !Task.isCancelled, model.dailyReminderStatus == .scheduled else { return }
            model.updateLearningSetup { $0.reminderEnabled = true }
        case .grading:
            do {
                let result: PlacementResult
                if let unsavedResult {
                    result = unsavedResult
                } else {
                    result = try await PlacementTest.grade(setup.answers, executablePath: codexPath)
                }
                try Task.checkCancellation()
                unsavedResult = result
                if model.updateLearningSetup({
                    $0.result = result
                    $0.stage = .result
                }) {
                    unsavedResult = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                testError = error.localizedDescription
            }
        }
    }

    private func title(_ text: String, _ detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(PlanStyle.title)
                .tracking(-0.35)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(PlanStyle.body)
                    .foregroundStyle(PlanStyle.secondary)
                    .lineSpacing(4)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(PlanStyle.caption)
            .foregroundStyle(PlanStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func choice(
        _ title: String, detail: String? = nil, icon: OnboardingIcon? = nil, selected: Bool,
        height: CGFloat = 52, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    iconTile(icon, size: 32, background: selected ? PlanStyle.card : PlanStyle.subtle, radius: 12)
                }
                Text(title).font(PlanStyle.label)
                Spacer(minLength: 4)
                if let detail { caption(detail) }
                ZStack {
                    if selected {
                        Circle().fill(PlanStyle.action)
                        OnboardingIcon.choiceCheck
                    } else {
                        Circle().strokeBorder(PlanStyle.connector)
                    }
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            }
        }
        .buttonStyle(SetupOutlineButtonStyle(height: height, radius: 16, selected: selected, control: true))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func iconTile(_ icon: OnboardingIcon, size: CGFloat, background: Color, radius: CGFloat) -> some View {
        icon.frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: radius))
    }

    private func feature(_ title: String, _ detail: String, icon: OnboardingIcon, tone: Tone) -> some View {
        HStack(spacing: 16) {
            iconTile(icon, size: 44, background: tone.background, radius: 12)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(PlanStyle.label)
                caption(detail)
            }
        }
        .planCard(padding: 16, radius: 16)
    }

    private func banner(_ title: String, _ detail: String, icon: OnboardingIcon, tone: Tone) -> some View {
        HStack(alignment: .top, spacing: 20) {
            iconTile(icon, size: 52, background: PlanStyle.card, radius: 12)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(PlanStyle.heading)
                Text(detail).font(PlanStyle.body).lineSpacing(4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .foregroundStyle(tone.foreground)
        .background(tone.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func notice(_ title: String, _ detail: String, icon: OnboardingIcon, tone: Tone) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon.frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(PlanStyle.label)
                Text(detail).font(PlanStyle.caption)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .foregroundStyle(tone.foreground)
        .background(tone.background, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private enum Tone {
        case brand, success, reward, error

        var background: Color {
            switch self {
            case .brand: PlanStyle.soft
            case .success: PlanStyle.successBackground
            case .reward: PlanStyle.rewardBackground
            case .error: Color(.setupErrorBackground)
            }
        }

        var foreground: Color {
            switch self {
            case .brand: PlanStyle.onSoft
            case .success: PlanStyle.success
            case .reward: PlanStyle.reward
            case .error: Color(.setupErrorText)
            }
        }
    }
}

private struct OnboardingSidebar: View {
    let stage: LearningSetup.Stage

    private var currentGroup: Int {
        switch stage {
        case .agent: 1
        case .testIntro, .test, .result, .complete: 3
        default: 2
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    OnboardingIcon.logo
                        .frame(width: 36, height: 36)
                        .background(PlanStyle.action, in: RoundedRectangle(cornerRadius: 12))
                    Text("English Practice")
                        .font(PlanStyle.heading)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.bottom, 24)

                Image(.setupHero)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(.horizontal, -4)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 12) {
                    Text(headline)
                        .font(PlanStyle.title)
                        .tracking(-0.35)
                        .accessibilityAddTraits(.isHeader)
                    Text(detail)
                        .font(PlanStyle.caption)
                        .lineSpacing(3)
                        .foregroundStyle(PlanStyle.secondary)
                }
                .padding(.top, 4)
                .frame(minHeight: 121, alignment: .topLeading)

                Rectangle().fill(PlanStyle.border).frame(height: 1)
                    .padding(.top, 43)
                    .padding(.bottom, 22)

                VStack(spacing: 16) {
                    step(1, "Подключи агента", "Codex и локальный MCP")
                    step(2, "Настрой обучение", "Цель, уровень и привычка")
                    step(3, "Проверь свой уровень", "Входной тест")
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .frame(maxHeight: .infinity)
        .background(PlanStyle.subtle)
    }

    private var headline: String {
        switch currentGroup {
        case 1: "Английский\nкаждый день"
        case 2: "Учись в своём\nтемпе"
        default: "Найди свою\nточку старта"
        }
    }

    private var detail: String {
        switch currentGroup {
        case 1: "Уроки и проверка ответов через твоего агента."
        case 2: "Выбери, зачем учишься и сколько времени готов уделять."
        default: "Начни с заданий, которые подходят твоему уровню."
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        let current = number == currentGroup
        let completed = number < currentGroup
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(current ? PlanStyle.action : (completed ? PlanStyle.successBackground : PlanStyle.card))
                if completed {
                    OnboardingIcon.stageCheck
                } else {
                    Text("0\(number)")
                        .font(PlanStyle.caption)
                        .foregroundStyle(current ? PlanStyle.onAction : PlanStyle.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PlanStyle.label)
                    .foregroundStyle(current ? PlanStyle.onSoft : PlanStyle.text)
                Text(detail)
                    .font(PlanStyle.caption)
                    .foregroundStyle(PlanStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityValue(current ? "Текущий этап" : (completed ? "Пройдено" : "Далее"))
    }
}

private extension LearningSetup.Motivation {
    var icon: OnboardingIcon {
        switch self {
        case .travel: .plane
        case .work: .briefcase
        case .communication: .chat
        case .study: .book
        case .personal: .star
        case .other: .plus
        }
    }
}
