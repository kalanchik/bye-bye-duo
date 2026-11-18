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
            Picker("Модель", selection: Binding(get: { settings.model ?? "" }, set: { id in
                save { $0.model = id.isEmpty ? nil : id; $0.effort = nil }
            })) {
                Text("По умолчанию для уроков").tag("")
                if let id = settings.model, !models.contains(where: { $0.model == id }) {
                    Text(id).tag(id)
                }
                ForEach(models) { Text($0.displayName).tag($0.model) }
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

    private func effortPicker(_ item: TutorModel, selected: String) -> some View {
        Picker("Уровень рассуждения", selection: Binding(get: { selected }, set: { value in
            save { $0.effort = value }
        })) {
            ForEach(item.supportedReasoningEfforts.map(\.reasoningEffort), id: \.self) { Text($0).tag($0) }
        }
    }

    private func number(_ label: String, _ key: WritableKeyPath<AgentSettings, Int>, _ bounds: ClosedRange<Int>) -> some View {
        Stepper(value: Binding(get: { settings[keyPath: key] }, set: { value in
            save { $0[keyPath: key] = value }
        }), in: bounds) {
            HStack {
                Text(label)
                Spacer()
                Text("\(settings[keyPath: key])").monospacedDigit()
            }
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

private struct PromptEditor: View {
    let kind: TutorPrompt
    let settings: AgentSettings
    let save: (String) throws -> Void
    @State private var editing = false
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        DisclosureGroup(kind.title) {
            VStack(alignment: .leading, spacing: 10) {
                if editing {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 130).accessibilityLabel("Текст промпта")
                    Text("Переменные").font(PlanStyle.label)
                    Text(settings.variables.keys.sorted().map { "{{\($0)}}" }.joined(separator: "  "))
                        .font(PlanStyle.caption).textSelection(.enabled)
                    DisclosureGroup("Предпросмотр") {
                        Text((try? settings.render(text)) ?? "Проверь текст и названия переменных.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Button("Сохранить") {
                            do {
                                _ = try settings.render(text)
                                try save(text)
                                editing = false
                                error = nil
                            } catch { self.error = error.localizedDescription }
                        }
                        Button("Отмена") { editing = false; error = nil }
                        Button("Вернуть исходный") { text = kind.original; error = nil }
                    }
                    if let error { Text(error).foregroundStyle(Color(.setupErrorText)) }
                } else {
                    Text(settings.template(kind)).textSelection(.enabled)
                    Button("Редактировать") { text = settings.template(kind); editing = true }
                }
            }
            .font(PlanStyle.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }
    }
}
