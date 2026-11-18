import SwiftUI

struct AgentSettingsView: View {
    let model: StudyModel
    let executablePath: String
    @State private var models: [TutorModel] = []
    @State private var catalogError: String?
    @State private var saveError: String?
    @State private var refresh = 0

    private var settings: AgentSettings { model.agentSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Агент").font(PlanStyle.heading).accessibilityAddTraits(.isHeader)
            StudyDropdown(label: "Модель", options: modelOptions, selected: settings.model ?? "") { id in
                save {
                    $0.model = id.isEmpty ? nil : id
                    $0.effort = nil
                }
            }
            if let selected = try? settings.selection(from: models),
               let item = models.first(where: { $0.model == selected.model }) {
                Text("Используется \(item.displayName) · \(selected.effort)")
                    .font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                if settings.model != nil && !item.supportedReasoningEfforts.isEmpty {
                    effortPicker(item, selected: selected.effort)
                }
            } else if let item = models.first(where: { $0.model == settings.model }) {
                effortPicker(item, selected: settings.effort ?? item.defaultReasoningEffort)
            } else if !models.isEmpty && settings.model != nil {
                Text("Сохранённая модель недоступна. Выбери другую модель.").font(PlanStyle.caption)
            }
            if let catalogError {
                Text(catalogError).foregroundStyle(Color(.setupErrorText))
            } else if models.isEmpty {
                ProgressView("Загрузка моделей…").controlSize(.small)
            }
            Button("Обновить список моделей") { refresh += 1 }
            Divider()
            Text("Структура раздела").font(PlanStyle.label)
            number("Уроков в разделе", \.lessonsPerSection, 1...5)
            number("Заданий для генерации в уроке и домашней работе", \.exercisesPerLesson, 20...30)
            number("Заданий для генерации в повторении", \.reviewExercises, 6...10)
            number("Карточек в разделе", \.cardsPerSection, 8...15)
            number("Заданий в контрольной", \.testExercises, 20...25)
            number("Проходной балл, %", \.passingPercent, 1...100)
            Text(settings.sectionSummary).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            Divider()
            Text("Промпты").font(PlanStyle.label)
            ForEach(TutorPrompt.allCases) { kind in
                PromptEditor(kind: kind, settings: settings) { template in
                    var updated = model.agentSettings
                    updated.prompts[kind.rawValue] = template == kind.original ? nil : template
                    try model.saveAgentSettings(updated)
                }
            }
            if let saveError { Text(saveError).foregroundStyle(Color(.setupErrorText)) }
        }
        .planCard(padding: 24)
        .task(id: CatalogKey(path: executablePath, refresh: refresh)) {
            models = []
            catalogError = nil
            do {
                let catalog = try await CodexReviewer.models(executablePath: executablePath)
                try Task.checkCancellation()
                models = catalog
                if catalog.isEmpty { catalogError = "Codex не вернул доступные модели." }
            } catch {
                if !Task.isCancelled { catalogError = error.localizedDescription }
            }
        }
    }

    private struct CatalogKey: Equatable { let path: String; let refresh: Int }

    private var modelOptions: [StudyDropdown.Option] {
        var options = [StudyDropdown.Option(id: "", title: "По умолчанию для уроков")]
        if let id = settings.model, !models.contains(where: { $0.model == id }) {
            options.append(.init(id: id, title: id))
        }
        return options + models.map { .init(id: $0.model, title: $0.displayName) }
    }

    private func effortPicker(_ item: TutorModel, selected: String) -> some View {
        let options = item.supportedReasoningEfforts.map { StudyDropdown.Option(id: $0.reasoningEffort, title: $0.reasoningEffort) }
        return StudyDropdown(label: "Уровень рассуждения", options: options, selected: selected) { value in
            save { $0.effort = value }
        }
    }

    private func number(_ label: String, _ key: WritableKeyPath<AgentSettings, Int>, _ bounds: ClosedRange<Int>) -> some View {
        SettingNumberField(label: label, bounds: bounds, value: settings[keyPath: key]) { value in
            save { $0[keyPath: key] = value }
        }
    }

    private func save(_ change: (inout AgentSettings) -> Void) {
        var settings = model.agentSettings
        change(&settings)
        do {
            try model.saveAgentSettings(settings)
            saveError = nil
        } catch { saveError = error.localizedDescription }
    }
}

private struct SettingNumberField: View {
    let label: String
    let bounds: ClosedRange<Int>
    let value: Int
    let save: (Int) -> Void

    @State private var draft: String?
    @State private var showsError = false
    @FocusState private var focused: Bool

    private var rangeHint: String { "Целое число от \(bounds.lowerBound) до \(bounds.upperBound)" }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 16) {
                Text(label).font(PlanStyle.body)
                Spacer(minLength: 0)
                TextField(label, text: Binding(get: { draft ?? String(value) }, set: {
                    draft = $0
                    showsError = false
                }))
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(PlanStyle.button.monospacedDigit())
                .frame(width: 48, height: 48)
                .background(PlanStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(showsError ? Color(.setupErrorText) : focused ? Color(.setupFocus) : PlanStyle.connector,
                                      lineWidth: focused ? 2 : 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
                .focused($focused)
                .accessibilityLabel(label)
                .accessibilityHint(rangeHint)
                .help(rangeHint)
                .onSubmit(commit)
                .onChange(of: focused) { _, active in if !active { commit() } }
                .onExitCommand { draft = nil; showsError = false }
            }
            if showsError {
                Text(rangeHint).font(PlanStyle.caption).foregroundStyle(Color(.setupErrorText))
            }
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        guard let draft else { return }
        guard let number = Int(draft.trimmed), bounds.contains(number) else {
            showsError = true
            return
        }
        if number != value { save(number) }
        self.draft = nil
        showsError = false
    }
}
