import SwiftUI

struct StudyPlanView: View {
    let model: StudyModel
    let open: (String) -> Void
    let openBuilder: () -> Void
    @State private var viewportWidth: CGFloat = 0
    @State private var continuation: StudySection?
    @State private var deepens = true

    private var next: Lesson? { model.nextLesson }

    var body: some View {
        let next = next
        ScrollView {
            let wide = viewportWidth >= 838
            let layout = wide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
            layout {
                if !wide {
                    context(next: next)
                }
                route(next: next)
                if wide {
                    context(next: next).frame(width: 250)
                }
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 32)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { viewportWidth = $0 }
        .background(PlanStyle.canvas)
        .foregroundStyle(PlanStyle.text)
        .font(PlanStyle.label)
        .sheet(item: $continuation) { section in continuationSheet(section) }
    }

    private func route(next: Lesson?) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(Array(model.routeSections.enumerated()), id: \.element.id) { index, section in
                if let first = section.entries.first {
                    let steps = steps(in: section)
                    VStack(alignment: .leading, spacing: 18) {
                        sectionBanner(first, number: index + 1, steps: steps)
                        PlanRoute(steps: steps, current: next?.id,
                                  linear: model.planning.route.contains { $0.id == section.id }
                                      && steps.allSatisfy { !$0.completed },
                                  select: open)
                        if section.completed(model.snapshot.progress),
                           section.entries.contains(where: { $0.lesson.levelTest == nil }) {
                            endOfSection(section)
                        }
                    }
                }
            }
            if !model.planning.firstPlanCreated && model.learningSetup?.stage == .complete {
                StudyAction("Составить первый план", spark: true) {
                    if model.beginPlan(.first) { openBuilder() }
                }
            }
            if let draft = model.planning.draft, draft.mode != .first {
                StudyAction(draft.stage == .ready ? "Открыть готовый план" : "Продолжить черновик") { openBuilder() }
            }
        }
    }

    private func steps(in section: StudySection) -> [PlanStep] {
        section.orderedEntries.map { entry in
            let lesson = entry.lesson
            let title = lesson.isCheckpoint && lesson.title.hasPrefix("Контрольная · ")
                ? String(lesson.title.dropFirst("Контрольная · ".count)) : lesson.title
            return PlanStep(
                id: lesson.id, title: title, kind: .init(lesson: lesson),
                completed: lesson.completed(model.progress(for: lesson.id))
            )
        }
    }

    private func sectionBanner(_ entry: CourseEntry, number: Int, steps: [PlanStep]) -> some View {
        let completed = steps.count(where: \.completed)
        return HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("РАЗДЕЛ \(number)").planPill(background: PlanStyle.card)
                Text(entry.section.title)
                    .font(PlanStyle.title)
                    .tracking(-0.35)
                    .accessibilityAddTraits(.isHeader)
                Text(model.planning.route.first { $0.id == "\(entry.module.id)/\(entry.section.id)" }?.topic.goal
                     ?? entry.module.title)
                    .font(PlanStyle.caption)
                    .foregroundStyle(PlanStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                Text("\(completed) из \(steps.count) шагов")
                    .font(PlanStyle.label)
                    .foregroundStyle(PlanStyle.onSoft)
                    .multilineTextAlignment(.trailing)
                PlanProgressBar(value: Double(completed) / Double(max(1, steps.count)), height: 6)
            }
            .frame(width: 132)
            .padding(.bottom, 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Прогресс раздела")
            .accessibilityValue("\(completed) из \(steps.count) шагов")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minHeight: 124)
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                PlanGraphic(.planOrnament, 113.5).opacity(0.8).padding(.top, 10).padding(.trailing, 11)
                PlanGraphic(.planSpark, 13.3333).padding(.top, 26).padding(.trailing, 132)
                PlanGraphic(.planSparkSmall, 7.5).padding(.top, 19).padding(.trailing, 16)
            }
        }
        .background(PlanStyle.soft)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func context(next: Lesson?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.planning.firstPlanCreated && !model.planning.route.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Твои темы").font(PlanStyle.heading)
                    ForEach(Array(model.planning.route.enumerated()), id: \.element.id) { index, section in
                        HStack(spacing: 10) {
                            Text(String(format: "%02d", index + 1)).planPill(background: PlanStyle.card)
                            Text(section.topic.title).font(PlanStyle.label)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(PlanStyle.subtle, in: RoundedRectangle(cornerRadius: 12))
                    }
                }.planCard()
            }
            if let next { nextCard(next) }
            levelCard
            goalCard
        }
    }

    private func endOfSection(_ section: StudySection) -> some View {
        VStack(spacing: 14) {
            StudyGraphic.moreFlag.frame(width: 48, height: 48)
                .background(PlanStyle.card, in: RoundedRectangle(cornerRadius: 14))
            Text("Раздел пройден").font(PlanStyle.heading)
            Text("Можно продолжить тему или выбрать новую.").font(PlanStyle.body)
                .foregroundStyle(PlanStyle.secondary)
            HStack {
                if !section.entries.contains(where: { $0.lesson.isCheckpoint }),
                   model.planning.route.contains(where: { $0.id == section.id }) {
                    Button("Проверить тему") {
                        if model.beginPlan(.checkpoint, section: section) { openBuilder() }
                    }.buttonStyle(StudySecondaryStyle())
                }
                StudyAction("Создать ещё") { deepens = true; continuation = section }
            }
        }
        .multilineTextAlignment(.center)
        .padding(22).frame(maxWidth: .infinity)
        .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 22))
    }

    private func continuationSheet(_ section: StudySection) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                StudyGraphic.moreSpark.frame(width: 44, height: 44)
                    .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                Button { continuation = nil } label: { StudyGraphic.moreClose }
                    .buttonStyle(StudySecondaryStyle()).accessibilityLabel("Закрыть")
            }
            Text("Что потренируем дальше?").font(PlanStyle.title)
            Text("Выбери направление для следующего раздела на \(model.studyLevel).")
                .font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
            StudyChoice(selected: deepens) { deepens = true } label: {
                continuationOption(StudyGraphic.morePencil, "Углубить тему",
                                   "Другие слова и ситуации из темы «\(section.entries.first?.section.title ?? "")».")
            }
            StudyChoice(selected: !deepens) { deepens = false } label: {
                continuationOption(StudyGraphic.moreBook, "Выбрать новую тему", "Выбрать из каталога или предложить свою.")
            }
            HStack {
                Button("Отмена") { continuation = nil }.buttonStyle(StudySecondaryStyle())
                Spacer()
                StudyAction("Продолжить") {
                    if model.beginPlan(.extend, section: section, deepen: deepens) {
                        continuation = nil
                        openBuilder()
                    }
                }
            }
        }
        .padding(24).frame(width: 540)
        .foregroundStyle(PlanStyle.text).background(PlanStyle.card)
    }

    private func continuationOption(_ icon: PlanGraphic, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            icon.frame(width: 36, height: 36).background(PlanStyle.card, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(PlanStyle.label)
                Text(detail).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            }
        }
    }

    private var levelCard: some View {
        let readiness = model.levelTestReadiness
        let detail = if readiness.passedSections < 3 {
            "Следующая практика продолжится на \(model.studyLevel)."
        } else if readiness.missingSkills.isEmpty {
            "Можно проверить текущий уровень."
        } else {
            "Пока мало данных по навыкам \(readiness.missingSkills.map { "«\($0.rawValue)»" }.joined(separator: ", "))."
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                StudyGraphic.moreFlag.frame(width: 42, height: 42)
                    .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 14))
                Text("ТВОЙ УРОВЕНЬ").font(PlanStyle.caption).foregroundStyle(PlanStyle.onSoft)
            }
            Text(model.levelBadge).font(PlanStyle.heading)
            Text(detail)
                .font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            if model.studyLevel != "C2" {
                Button("Пройти тест \(model.studyLevel)") {
                    if let existing = model.snapshot.entries.first(where: { $0.lesson.levelTest == model.studyLevel }) {
                        open(existing.lesson.id)
                    } else if model.beginPlan(.levelTest) {
                        openBuilder()
                    }
                }.buttonStyle(StudySecondaryStyle())
            }
        }.planCard()
    }

    private func nextCard(_ lesson: Lesson) -> some View {
        let progress = model.progress(for: lesson.id)
        let exercises = lesson.includingVocabulary(progress.vocabularyCards ?? []).exercises
        let answered = exercises.count { progress.draft[$0.id]?.trimmed.isEmpty == false }
        let description = lesson.theory.components(separatedBy: "\n\n").first?.trimmed ?? ""
        let hasDraft = !progress.finished && answered > 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PlanGraphic(.planPencil, 17.8)
                    .frame(width: 44, height: 44)
                    .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 14))
                Text("СЛЕДУЮЩИЙ ШАГ")
                    .font(PlanStyle.caption)
                    .foregroundStyle(PlanStyle.onSoft)
            }
            Text(lesson.title)
                .font(PlanStyle.heading)
                .accessibilityAddTraits(.isHeader)
            if !description.isEmpty {
                Text(.init(description))
                    .font(PlanStyle.caption)
                    .foregroundStyle(PlanStyle.secondary)
                    .lineLimit(3)
            }
            Button {
                open(lesson.id)
            } label: {
                HStack(spacing: 12) {
                    Text("Продолжить")
                    PlanGraphic(.planArrow, 12.6, 10.35)
                }
            }
            .buttonStyle(PlanPrimaryButtonStyle())
            if hasDraft {
                Text("Черновик · \(answered) из \(exercises.count) заданий")
                    .font(PlanStyle.caption)
                    .foregroundStyle(PlanStyle.secondary)
            } else {
                Text(lesson.status(for: progress))
                    .font(PlanStyle.caption)
                    .foregroundStyle(PlanStyle.secondary)
            }
        }
        .planCard()
    }

    private var goalCard: some View {
        let seconds = max(0, Int(model.todayStudySeconds))
        let goal = model.dailyGoalMinutes
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PlanGraphic(.planClock, 16.5)
                    .frame(width: 38, height: 38)
                    .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 14))
                Text("Цель на сегодня").font(PlanStyle.label)
            }
            Text("\(seconds / 60) из \(goal) минут")
                .font(PlanStyle.heading)
                .accessibilityValue("\(seconds / 60) мин \(seconds % 60) с из \(goal) мин")
            PlanProgressBar(value: Double(seconds) / Double(goal * 60), height: 7)
        }
        .planCard()
        .accessibilityElement(children: .combine)
    }
}

private struct PlanStep: Identifiable {
    enum Kind: String {
        case lesson = "Урок"
        case practice = "Практика"
        case listening = "Аудирование"
        case checkpoint = "Контрольная"
        case story = "История"
        case review = "Повторение"

        init(lesson: Lesson) {
            if lesson.isCheckpoint {
                self = .checkpoint
            } else if lesson.kind == .story {
                self = .story
            } else if lesson.title.hasPrefix("Повторение") {
                self = .review
            } else if lesson.exercises.allSatisfy({ $0.speechText != nil }) {
                self = .listening
            } else if lesson.kind == .homework {
                self = .practice
            } else {
                self = .lesson
            }
        }

        func icon(current: Bool, completed: Bool) -> PlanGraphic {
            let tint: Color? = if current && self != .practice {
                PlanStyle.onAction
            } else if completed && self != .lesson {
                PlanStyle.success
            } else if !current && !completed && (self == .lesson || self == .checkpoint) {
                PlanStyle.onSoft
            } else {
                nil
            }

            return switch self {
            case .lesson: PlanGraphic(.planBook, 21.45, 20.562, tint: tint)
            case .practice:
                current ? PlanGraphic(.planCurrentPencil, 22.25) : PlanGraphic(.planPencil, 17.8, tint: tint)
            case .listening: PlanGraphic(.planHeadphones, 19.2833, 18.2, tint: tint)
            case .checkpoint, .review: PlanGraphic(.planFlag, 17.1167, 20.5341, tint: tint)
            case .story: PlanGraphic(.routeStory, StudyGraphic.routeStory.width, StudyGraphic.routeStory.height,
                                     tint: current ? PlanStyle.onAction : completed ? nil : PlanStyle.onSoft)
            }
        }
    }

    let id: String
    let title: String
    let kind: Kind
    let completed: Bool
}

private struct PlanRoute: View {
    let steps: [PlanStep]
    let current: String?
    var linear = false
    let select: (String) -> Void

    @State private var width: CGFloat = 500

    private let offsets: [CGFloat] = [-56, 9, -32, -94, 6, -43]
    private let leadingLabels = [1, 5]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("МАРШРУТ РАЗДЕЛА")
                .font(PlanStyle.caption)
                .foregroundStyle(PlanStyle.secondary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    let slot = index % offsets.count
                    let compact = width < 390
                    let center = compact ? 41 : width / 2 + (linear ? 0 : offsets[slot])
                    let isCurrent = step.id == current
                    Button {
                        select(step.id)
                    } label: {
                        row(step, current: isCurrent, x: center, labelOnLeft: !compact && !linear && leadingLabels.contains(slot))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(step.kind.rawValue) · \(step.title)")
                    .accessibilityValue(isCurrent ? "Следующий шаг" : (step.completed ? "Пройдено" : "К выполнению"))
                }
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            .backgroundPreferenceValue(RouteAnchors.self) { anchors in
                GeometryReader { geometry in
                    Path { path in
                        path.addLines(steps.compactMap { step in
                            anchors[step.id].map { geometry[$0] }
                        })
                    }
                    .stroke(PlanStyle.connector.opacity(0.65),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 9]))
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
        }
        .planCard(padding: 20, radius: 24)
    }

    private func row(_ step: PlanStep, current: Bool, x: CGFloat, labelOnLeft: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if labelOnLeft {
                    stepLabel(step, current: current, alignment: .trailing)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(width: max(0, x - 49))

            marker(step, current: current)
                .frame(width: 82, height: 82)
                .anchorPreference(key: RouteAnchors.self, value: .center) { [step.id: $0] }

            if !labelOnLeft {
                stepLabel(step, current: current, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func marker(_ step: PlanStep, current: Bool) -> some View {
        ZStack(alignment: .center) {
            if current {
                PlanGraphic(.planCurrentRing, 82).offset(y: -1)
                PlanGraphic(.planCurrentEdge, 68).offset(y: 5)
                PlanGraphic(.planCurrentDisc, 68).offset(y: 1)
            } else {
                PlanGraphic(step.completed ? .planCompletedEdge : .planPendingEdge, 60).offset(y: 5)
                PlanGraphic(step.completed ? .planCompletedDisc : .planPendingDisc, 60).offset(y: 1)
            }
            step.kind.icon(current: current, completed: step.completed)
                .offset(y: 1)
            if step.completed {
                PlanGraphic(.planCheck, 8.55833, 6.39167)
                    .frame(width: 23, height: 23)
                    .background(PlanStyle.card, in: Circle())
                    .overlay { Circle().strokeBorder(PlanStyle.successBackground) }
                    .offset(x: 24.5, y: 21.5)
            }
        }
    }

    private func stepLabel(_ step: PlanStep, current: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(step.kind.rawValue.uppercased())
                .font(PlanStyle.caption)
                .foregroundStyle(current ? PlanStyle.onSoft : PlanStyle.secondary)
            Text(step.title)
                .font(current ? PlanStyle.button : PlanStyle.label)
                .fixedSize(horizontal: false, vertical: true)
            if current {
                Text("Продолжить").planPill()
            }
        }
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

private struct RouteAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGPoint>] = [:]

    static func reduce(value: inout [String: Anchor<CGPoint>],
                       nextValue: () -> [String: Anchor<CGPoint>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
