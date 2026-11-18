import SwiftUI

struct PlanBuilderView: View {
    let model: StudyModel
    let back: () -> Void
    let open: (String) -> Void

    @AppStorage("codexPath") private var codexPath = CodexReviewer.detectedPath
    @State private var custom = ""
    @State private var note = ""
    @State private var showsNote = false
    @State private var generation: Task<Void, Never>?
    @State private var viewportWidth: CGFloat = 0

    private var draft: PlanDraft { model.planning.draft ?? PlanDraft(mode: .first) }
    private var limit: Int { draft.mode == .first ? 3 : 1 }
    private var first: Bool { draft.mode == .first }
    private var running: Bool { model.generationPhase != nil }
    private var title: String {
        switch draft.mode {
        case .first: "Первый план обучения"
        case .extend: "Следующая практика"
        case .checkpoint: "Контрольная по теме"
        case .levelTest: "Проверка уровня"
        }
    }

    var body: some View {
        StudyWorkspace(width: draft.stage == .topics && !running ? 1100 : 592) {
            if running {
                working
            } else {
                switch draft.stage {
                case .topics: topics
                case .review: review
                case .interrupted: interrupted
                case .ready: ready
                }
            }
        } footer: {
            footer
        }
        .navigationTitle(title)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { viewportWidth = $0 }
        .toolbar {
            if !running && draft.stage != .ready {
                ToolbarItem(placement: .navigation) {
                    StudyBackButton {
                        if draft.stage == .topics || draft.mode == .checkpoint || draft.mode == .levelTest { back() }
                        else { go(.topics) }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Text(running ? "ГЕНЕРАЦИЯ" : toolbarBadge).planPill()
            }
        }
        .sheet(isPresented: $showsNote) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    StudyGraphic.moreSpark.frame(width: 44, height: 44)
                        .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 12))
                    Spacer()
                    Button { showsNote = false } label: { StudyGraphic.moreClose }
                        .buttonStyle(StudySecondaryStyle()).accessibilityLabel("Закрыть")
                }
                Text("Пожелания к плану").font(PlanStyle.title)
                Text("Уровень и темы уже учтены. Добавь пожелание, если хочешь уточнить задания.")
                    .font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
                TextEditor(text: $note).scrollContentBackground(.hidden)
                    .font(PlanStyle.body).padding(8).frame(height: 100)
                    .background(PlanStyle.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PlanStyle.connector).allowsHitTesting(false) }
                    .accessibilityLabel("Пожелание к плану")
                Text("Например, добавь больше диалогов для поездок.").font(PlanStyle.caption)
                    .foregroundStyle(PlanStyle.secondary)
                HStack {
                    Button("Без контекста") { submit("") }.buttonStyle(StudySecondaryStyle())
                    Spacer()
                    StudyAction("Сгенерировать", disabled: note.trimmed.isEmpty, spark: true) { submit(note) }
                }
            }
            .padding(24).frame(width: 545)
            .background(PlanStyle.card).foregroundStyle(PlanStyle.text)
        }
        .onDisappear { generation?.cancel() }
    }

    private var toolbarBadge: String {
        switch draft.stage {
        case .topics: "ШАГ 1 ИЗ 2"
        case .review: "ШАГ 2 ИЗ 2"
        case .interrupted: "ГЕНЕРАЦИЯ"
        case .ready: "ПЛАН ГОТОВ"
        }
    }

    private var topics: some View {
        let recommendations = StudyTopic.recommendations(for: model.learningSetup?.motivation)
        let wide = viewportWidth >= 980
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
        return layout {
            topicCatalog(recommendations).frame(maxWidth: .infinity, alignment: .leading)
            sidebar.frame(width: wide ? 300 : nil)
        }
    }

    private func topicCatalog(_ recommendations: [String]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(first ? "Выбери темы для первого плана" : "Выбери новую тему",
                    first ? "Возьми от одной до трёх ситуаций, в которых хочешь говорить по-английски."
                          : "Выбери одну ситуацию для следующего раздела.")
            Text(recommendationHeading).font(PlanStyle.heading).padding(.top, 10)
            topicGrid(recommendations.compactMap { id in StudyTopic.catalog.first { $0.id == id } })
            Text("Все остальные темы").font(PlanStyle.heading).padding(.top, 5)
            topicGrid(StudyTopic.catalog.filter { !recommendations.contains($0.id) })
        }
    }

    private var recommendationHeading: String {
        switch model.learningSetup?.motivation {
        case .travel: "Рекомендуем для путешествий"
        case .work: "Рекомендуем для работы"
        case .communication: "Рекомендуем для общения"
        case .study: "Рекомендуем для учёбы"
        default: "Рекомендуем для начала"
        }
    }

    private func topicGrid(_ topics: [StudyTopic]) -> some View {
        let columns = viewportWidth >= 980
            ? Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
            : [GridItem(.adaptive(minimum: 200), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(topics) { topic in
                let selected = draft.selected.contains { $0.id == topic.id }
                Button { toggle(topic) } label: {
                    HStack(spacing: 9) {
                        PlanGraphic(topicIcon(topic), 20)
                            .frame(width: 34, height: 34)
                            .background(topic.id == "cafe" ? PlanStyle.rewardBackground
                                        : topic.id == "hotel" ? PlanStyle.successBackground
                                        : topic.id == "transport" ? PlanStyle.soft : PlanStyle.subtle,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(topic.title).font(PlanStyle.label).padding(.trailing, 19)
                            Text(catalogCaption(topic)).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    }
                    .padding(10).frame(minHeight: 69)
                    .background(PlanStyle.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topTrailing) {
                        ZStack {
                            if selected {
                                Circle().fill(PlanStyle.action)
                                PlanGraphic(.topicCheck, 13)
                            } else {
                                Circle().strokeBorder(PlanStyle.connector)
                            }
                        }
                        .frame(width: 17, height: 17).padding(10)
                        .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? PlanStyle.action : PlanStyle.border,
                                                                         lineWidth: selected ? 2 : 1)
                            .allowsHitTesting(false)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(first && !selected && draft.selected.count >= limit)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func catalogCaption(_ topic: StudyTopic) -> String {
        switch topic.id {
        case "introductions": "Представиться"
        case "cafe": "Заказать еду"
        case "work": "Рассказать о работе"
        default: topic.goal
        }
    }

    private func topicIcon(_ topic: StudyTopic) -> ImageResource {
        switch topic.id {
        case "introductions": .topicIntroductions
        case "family": .topicFamily
        case "morning": .topicMorning
        case "home": .topicHome
        case "cafe": .topicCafe
        case "shopping": .topicShopping
        case "directions": .topicDirections
        case "transport": .topicTransport
        case "hotel": .topicHotel
        case "work": .topicWork
        case "hobbies": .topicHobbies
        default: .topicMeeting
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                PlanGraphic(.topicRoute, 20).frame(width: 38, height: 38)
                    .background(PlanStyle.card, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.levelBadge).font(PlanStyle.label)
                    Text("\(model.dailyGoalMinutes) минут в день").font(PlanStyle.caption)
                }
            }
            .foregroundStyle(PlanStyle.onSoft)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(first ? "В первом плане" : "Следующая тема").font(PlanStyle.heading)
                    Spacer(minLength: 4)
                    Text("\(draft.selected.count) из \(limit)").planPill()
                }
                if draft.selected.isEmpty {
                    Text("Выбранные темы появятся здесь.").font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                }
                ForEach(Array(draft.selected.enumerated()), id: \.element.id) { index, topic in
                    HStack {
                        numberBadge(index + 1)
                        Text(topic.title).font(PlanStyle.label)
                        Spacer(minLength: 0)
                        Button { toggle(topic) } label: { PlanGraphic(.topicClose, 16).frame(width: 36, height: 36) }
                            .buttonStyle(.plain).accessibilityLabel("Убрать тему \(topic.title)")
                    }
                    .padding(.leading, 8).background(PlanStyle.subtle, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(minHeight: 204, alignment: .topLeading)
            .planCard()

            VStack(alignment: .leading, spacing: 11) {
                Text("Мои темы").font(PlanStyle.heading)
                Text("Свои темы останутся здесь для следующих планов.").font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                ForEach(model.planning.customTopics) { topic in
                    StudyChoice(selected: draft.selected.contains { $0.id == topic.id }) {
                        toggle(topic)
                    } label: { Text(topic.title).font(PlanStyle.label) }
                    .disabled(first && draft.selected.count >= limit && !draft.selected.contains { $0.id == topic.id })
                }
                TextField("Например, собеседование", text: $custom)
                    .textFieldStyle(.plain).font(PlanStyle.caption).padding(11)
                    .background(PlanStyle.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PlanStyle.connector).allowsHitTesting(false) }
                    .onSubmit(addTopic)
                Button(action: addTopic) {
                    HStack(spacing: 10) {
                        Text("Добавить тему")
                        PlanGraphic(.topicPlus, 18, tint: custom.trimmed.isEmpty ? Color(.setupOnDisabled) : PlanStyle.onAction)
                    }
                }
                    .buttonStyle(PlanPrimaryButtonStyle()).disabled(custom.trimmed.isEmpty)
            }
            .planCard()
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading(first ? "Проверь первый план" : "Проверь следующий шаг",
                    first ? "Агент подготовит по одному разделу для каждой темы." : reviewDescription)
            HStack(spacing: 18) {
                info(PlanGraphic(.topicRoute, 20), model.levelBadge, "Учебный уровень")
                info(PlanGraphic(.firstReview2, 16.4167, tint: PlanStyle.onSoft),
                     "\(model.dailyGoalMinutes) минут в день", "Дневная цель")
            }
            .padding(14).background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 16))
            topicList(heading: first ? "Темы плана" : "Что будем тренировать", reviewed: true)
        }
        .padding(.top, 9)
    }

    private var reviewDescription: String {
        switch draft.mode {
        case .checkpoint, .levelTest: "20–25 заданий на новых примерах. Для зачёта нужно 80% верных ответов."
        default: "Codex подготовит раздел с новыми словами, заданиями и повторением."
        }
    }

    private var working: some View {
        VStack(alignment: .leading, spacing: 20) {
            PlanGraphic(.planLoading, 24, tint: PlanStyle.onSoft).frame(width: 52, height: 52)
                .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 14))
            heading(first ? "Составляем первый план" : "Готовим следующую практику",
                    "Codex готовит задания для выбранных тем.")
            VStack(spacing: 8) {
                progressRow(0, "Подбираем порядок тем", "Уровень и цель на день задают сложность и темп.")
                progressRow(1, "Готовим первые задания", "Агент подбирает лексику, примеры и практику.")
                progressRow(2, "Сохраняем маршрут", "План появится на главной странице.")
            }
            .planCard(padding: 12)
        }
        .padding(.top, 12)
    }

    private func progressRow(_ index: Int, _ title: String, _ detail: String) -> some View {
        let phase = model.generationPhase ?? 0
        return HStack(spacing: 14) {
            Group {
                if index == phase { ProgressView().controlSize(.small) }
                else if index < phase { OnboardingIcon.success }
                else if index == 1 { StudyGraphic.moreBook }
                else { StudyGraphic.moreFlag }
            }
            .frame(width: 40, height: 40)
            .background(index < phase ? PlanStyle.successBackground : PlanStyle.card, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(PlanStyle.label)
                Text(detail).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(index == phase ? PlanStyle.soft : .clear, in: RoundedRectangle(cornerRadius: 14))
    }

    private var interrupted: some View {
        VStack(alignment: .leading, spacing: 15) {
            PlanGraphic(.planInterrupted, 24, tint: Color(.setupErrorText)).frame(width: 46, height: 46)
                .background(PlanStyle.card, in: RoundedRectangle(cornerRadius: 14))
            Text("Не удалось составить план").font(PlanStyle.title)
            Text("Темы и пожелание остались в черновике. Можно повторить запрос или изменить темы.").font(PlanStyle.body)
            if let error = model.generationError {
                Text(error).font(PlanStyle.caption).textSelection(.enabled)
            }
        }
        .padding(22).frame(maxWidth: .infinity, minHeight: 224, alignment: .topLeading)
        .foregroundStyle(Color(.setupErrorText))
        .background(Color(.setupErrorBackground), in: RoundedRectangle(cornerRadius: 22))
        .padding(.top, 36)
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 15) {
                PlanGraphic(.planReady, 24, tint: PlanStyle.success).frame(width: 50, height: 50)
                    .background(PlanStyle.card, in: RoundedRectangle(cornerRadius: 14))
                Text(first ? "Твой первый план готов" : "Следующая практика готова").font(PlanStyle.title)
                Text(first ? "Начни с первого раздела в своём темпе." : "Новый шаг добавлен в учебный план.")
                    .font(PlanStyle.body)
            }
            .padding(20).frame(maxWidth: .infinity, minHeight: 185, alignment: .leading)
            .foregroundStyle(PlanStyle.success)
            .background(PlanStyle.successBackground, in: RoundedRectangle(cornerRadius: 22))
            topicList(heading: first ? "Твой маршрут" : "Готово", reviewed: false)
        }
        .padding(.top, 9)
    }

    private func info(_ graphic: PlanGraphic, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            graphic.frame(width: 38, height: 38)
                .background(PlanStyle.card, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(PlanStyle.label)
                Text(detail).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(PlanStyle.display).accessibilityAddTraits(.isHeader)
            Text(detail).font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
        }
    }

    private func topicList(heading: String, reviewed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(heading).font(PlanStyle.heading)
                Spacer()
                Text("\(draft.selected.count) \(draft.selected.count == 1 ? "раздел" : "раздела")")
                    .font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            }
            ForEach(Array(draft.selected.enumerated()), id: \.element.id) { index, topic in
                HStack(spacing: 10) {
                    numberBadge(index + 1)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(topic.title).font(PlanStyle.label)
                        Text(topic.goal).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                    }
                    Spacer()
                }
                .planCard(padding: 10, radius: 12)
            }
            Spacer(minLength: 0)
            if reviewed && (draft.mode == .first || draft.mode == .extend) {
                Divider()
                Text("В первом уроке около 24 заданий. Его можно пройти за несколько сессий.")
                    .font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            }
        }
        .frame(minHeight: 284, alignment: .top)
        .planCard()
    }

    private func numberBadge(_ number: Int) -> some View {
        Text(String(format: "%02d", number)).font(PlanStyle.caption)
            .foregroundStyle(PlanStyle.onSoft).frame(width: 27, height: 27)
            .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            if running {
                Text("Темы уже сохранены в приложении").font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                Spacer()
                Button("Остановить") { generation?.cancel() }.buttonStyle(StudySecondaryStyle())
            } else {
                switch draft.stage {
                case .topics:
                    Text("Темы сохраняются в приложении").font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                    Spacer()
                    StudyAction("К проверке плана", disabled: draft.selected.isEmpty) { go(.review) }
                case .review:
                    Button(draft.mode == .checkpoint || draft.mode == .levelTest ? "К маршруту" : "Изменить темы") {
                        if draft.mode == .checkpoint || draft.mode == .levelTest { back() } else { go(.topics) }
                    }.buttonStyle(StudySecondaryStyle())
                    Spacer()
                    StudyAction("Сгенерировать", spark: true) { note = draft.note; showsNote = true }
                case .interrupted:
                    Button(draft.mode == .checkpoint || draft.mode == .levelTest ? "К маршруту" : "К темам") {
                        if draft.mode == .checkpoint || draft.mode == .levelTest { back() } else { go(.topics) }
                    }.buttonStyle(StudySecondaryStyle())
                    Spacer()
                    StudyAction("Повторить") { submit(draft.note) }
                case .ready:
                    Spacer()
                    StudyAction(draft.mode == .checkpoint || draft.mode == .levelTest ? "Открыть контрольную" : "Открыть маршрут") {
                        let test = draft.mode == .checkpoint || draft.mode == .levelTest
                        let id = model.snapshot.entries.first { $0.lesson.id.hasPrefix("plan-\(draft.requestKey)-") }?.lesson.id
                        let completedRequest = model.updatePlanning { $0.draft = nil }
                        if completedRequest, test, let id { open(id) } else { back() }
                    }
                }
            }
        }
    }

    private func go(_ stage: PlanDraft.Stage) {
        model.updatePlanning { $0.draft?.stage = stage }
    }

    private func toggle(_ topic: StudyTopic) {
        model.updatePlanning {
            guard var draft = $0.draft else { return }
            if draft.selected.contains(where: { $0.id == topic.id }) { draft.selected.removeAll { $0.id == topic.id } }
            else if first, draft.selected.count < limit { draft.selected.append(topic) }
            else if !first { draft.selected = [topic] }
            draft.prepared = []
            $0.draft = draft
        }
    }

    private func addTopic() {
        let title = String(custom.trimmed.prefix(100))
        guard !title.isEmpty else { return }
        if let topic = model.planning.topics.first(where: { $0.title.normalizedAnswer == title.normalizedAnswer }) {
            if !draft.selected.contains(where: { $0.id == topic.id }) { toggle(topic) }
            custom = ""
            return
        }
        let topic = StudyTopic(id: "custom-" + UUID().uuidString.lowercased(), title: title,
                               goal: "Потренироваться в выбранной ситуации")
        if model.updatePlanning({ state in
            state.customTopics.append(topic)
            if first, (state.draft?.selected.count ?? 0) < limit { state.draft?.selected.append(topic) }
            else if !first { state.draft?.selected = [topic] }
            state.draft?.prepared = []
        }) { custom = "" }
    }

    private func submit(_ text: String) {
        showsNote = false
        generation = Task {
            await model.generatePlan(note: String(text.trimmed.prefix(1_500)), executablePath: codexPath.trimmed)
        }
    }
}
