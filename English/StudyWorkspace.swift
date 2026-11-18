import SwiftUI

struct StudyWorkspace<Content: View, Footer: View>: View {
    var width: CGFloat = 592
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .frame(maxWidth: width, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
            }
            Rectangle().fill(PlanStyle.border).frame(height: 1)
            footer
                .frame(maxWidth: width, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
        }
        .background(PlanStyle.canvas)
        .foregroundStyle(PlanStyle.text)
    }
}

struct StudyBackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { StudyGraphic.practiceBack }
            .accessibilityLabel("Назад")
            .help("Назад")
    }
}

struct StudyAction: View {
    let title: String
    var disabled = false
    var spark = false
    let action: () -> Void

    init(_ title: String, disabled: Bool = false, spark: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.disabled = disabled
        self.spark = spark
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                if spark { PlanGraphic(.firstReview3, 15, tint: disabled ? Color(.setupOnDisabled) : PlanStyle.onAction) }
                else if disabled { OnboardingIcon.arrowDisabled }
                else { OnboardingIcon.arrow }
            }
            .frame(minWidth: 148)
            .padding(.horizontal, 8)
        }
        .buttonStyle(PlanPrimaryButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
        .disabled(disabled)
    }
}

struct StudySecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        configuration.label
            .font(PlanStyle.button)
            .foregroundStyle(PlanStyle.onSoft)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .background(configuration.isPressed ? PlanStyle.soft : PlanStyle.card, in: shape)
            .overlay { shape.strokeBorder(PlanStyle.border).allowsHitTesting(false) }
            .contentShape(shape)
    }
}

struct StudyChoice<Label: View>: View {
    let selected: Bool
    var result: Bool?
    let action: () -> Void
    @ViewBuilder let label: Label

    private var tint: Color {
        if let result { return result ? PlanStyle.success : Color(.setupErrorText) }
        return selected ? PlanStyle.action : PlanStyle.connector
    }

    private var background: Color {
        if let result { return result ? PlanStyle.successBackground : Color(.setupErrorBackground) }
        return selected ? PlanStyle.soft : PlanStyle.card
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                label
                Spacer(minLength: 8)
                ZStack {
                    if let result {
                        Circle().fill(tint)
                        if result { StudyGraphic.practiceGood }
                        else { StudyGraphic.practiceWrong }
                    } else if selected {
                        Circle().fill(tint)
                        OnboardingIcon.choiceCheck
                    } else {
                        Circle().strokeBorder(tint)
                    }
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            }
            .foregroundStyle(result == nil ? PlanStyle.text : tint)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .frame(minHeight: 52)
            .background(background, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(tint, lineWidth: selected || result != nil ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(result.map { $0 ? "Верный ответ" : "Неверный ответ" } ?? "")
    }
}

struct LessonResultView: View {
    let entry: CourseEntry
    let attempt: Attempt
    let firstAttempt: Attempt
    let back: () -> Void
    let retry: () -> Void
    var acceptLevel: (() -> Void)?

    private var celebration: LessonCelebration {
        attempt.celebration ?? (entry.lesson.isCheckpoint && !entry.lesson.passed(attempt) ? .checkpointFailed : .completed)
    }

    var body: some View {
        StudyWorkspace {
            VStack(spacing: 22) {
                VStack(spacing: 16) {
                    ornament
                    Text(badge).font(PlanStyle.caption).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(PlanStyle.card, in: Capsule())
                    Text(title).font(PlanStyle.display).accessibilityAddTraits(.isHeader)
                    Text(detail).font(PlanStyle.body)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 354)
                .background(background, in: RoundedRectangle(cornerRadius: 24))
                HStack(alignment: .top, spacing: 16) {
                    metric("\(firstAttempt.correctCount) из \(firstAttempt.feedback.count)", "верно с первой попытки", clock: false)
                    if let duration = attempt.studySeconds {
                        let value = duration < 60 ? "\(Int(duration)) с" : "\(Int(duration / 60)) мин"
                        metric(value, "время практики", clock: true)
                    }
                }
                if entry.lesson.levelTest != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Результаты по навыкам").font(PlanStyle.heading)
                        ForEach(entry.lesson.levelEvidence(for: attempt), id: \.skill) { score in
                            HStack {
                                Text(score.skill.rawValue)
                                Spacer()
                                Text("\(score.correct) из \(score.total) · \(score.strong ? "Получается" : "Стоит повторить")")
                            }.font(PlanStyle.caption)
                        }
                    }.planCard()
                }
            }
            .padding(.top, 24)
        } footer: {
            HStack {
                if celebration == .checkpointFailed {
                    Button("Пересдать", action: retry).buttonStyle(StudySecondaryStyle())
                }
                Spacer()
                if let acceptLevel, entry.lesson.passed(attempt) {
                    Button("К маршруту", action: back).buttonStyle(StudySecondaryStyle())
                    StudyAction("Начать следующий уровень", action: acceptLevel)
                } else {
                    StudyAction("К маршруту", action: back)
                }
            }
        }
    }

    private var ornament: some View {
        let graphics: [PlanGraphic]
        switch celebration {
        case .streak:
            graphics = [StudyGraphic.resultStreak1, StudyGraphic.resultStreak2, StudyGraphic.resultStreak3,
                        StudyGraphic.resultStreak4, StudyGraphic.resultStreak5, StudyGraphic.resultStreak6]
        case .perfect:
            graphics = [StudyGraphic.resultPerfect1, StudyGraphic.resultPerfect2, StudyGraphic.resultPerfect3,
                        StudyGraphic.resultPerfect4, StudyGraphic.resultPerfect5, StudyGraphic.resultPerfect6]
        case .story:
            graphics = [StudyGraphic.resultStory1, StudyGraphic.resultStory2, StudyGraphic.resultStory3,
                        StudyGraphic.resultStory4, StudyGraphic.resultStory5, StudyGraphic.resultStory6]
        default:
            graphics = [StudyGraphic.resultStandard1, StudyGraphic.resultStandard2, StudyGraphic.resultStandard3,
                        StudyGraphic.resultStandard4, StudyGraphic.resultStandard5, StudyGraphic.resultStandard6]
        }
        return ZStack {
            graphics[0]
            Circle().fill(PlanStyle.card).frame(width: 106, height: 106)
            graphics[5]
            graphics[1].offset(x: -102, y: -17)
            graphics[2].offset(x: 108, y: -39)
            graphics[3].offset(x: 88, y: 40)
            graphics[4].offset(x: -90, y: 45)
        }
        .frame(width: 240, height: 154)
        .accessibilityHidden(true)
    }

    private func metric(_ value: String, _ label: String, clock: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if clock { OnboardingIcon.clock } else { OnboardingIcon.menuCheck }
            }
            .frame(width: 36, height: 36)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(value).font(PlanStyle.heading)
                Text(label).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56, alignment: .topLeading)
        .planCard()
    }

    private var foreground: Color {
        switch celebration {
        case .streak: PlanStyle.reward
        case .perfect: PlanStyle.success
        case .checkpointFailed: Color(.setupErrorText)
        default: PlanStyle.onSoft
        }
    }

    private var background: Color {
        switch celebration {
        case .streak: PlanStyle.rewardBackground
        case .perfect: PlanStyle.successBackground
        case .checkpointFailed: Color(.setupErrorBackground)
        default: PlanStyle.soft
        }
    }

    private var badge: String {
        switch celebration {
        case .streak: "СЕРИЯ ВЕРНЫХ ОТВЕТОВ"
        case .perfect: "УРОК БЕЗ ОШИБОК"
        case .story: "ИСТОРИЯ ЗАВЕРШЕНА"
        case .checkpointFailed: "КОНТРОЛЬНАЯ"
        case .completed: entry.lesson.isCheckpoint ? "КОНТРОЛЬНАЯ СДАНА" : "УРОК ЗАВЕРШЁН"
        }
    }

    private var title: String {
        switch celebration {
        case .streak: "Вот это серия!"
        case .perfect: "Ни одной ошибки!"
        case .story: "История завершена"
        case .checkpointFailed: "Нужно ещё потренироваться"
        case .completed: "Отличная работа!"
        }
    }

    private var detail: String {
        switch celebration {
        case .streak: "10 верных ответов подряд. Так держать!"
        case .perfect: "Все ответы верны с первой попытки."
        case .story: "Ты прочитал историю «\(entry.lesson.title)» и ответил на вопросы."
        case .checkpointFailed:
            entry.lesson.levelTest == nil
                ? "Верно \(attempt.correctCount) из \(attempt.feedback.count). Для зачёта нужно \(entry.lesson.passingPercent ?? 80)%."
                : "Для зачёта нужно 80% верных ответов и не меньше 60% по каждому навыку."
        case .completed: "Ты потренировался в разделе «\(entry.section.title)»."
        }
    }
}
