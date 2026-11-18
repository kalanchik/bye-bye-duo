import SwiftUI

struct StreakView: View {
    let model: StudyModel
    let back: () -> Void
    let continueStudy: () -> Void

    @AppStorage("streakGoalDays") private var goal = 5
    @AppStorage("streakAchievement") private var lastAchievement = ""
    @AppStorage("streakAnimatedDay") private var lastAnimatedDay = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = Page.running
    @State private var chosen: Int?
    @State private var displayCount: Int?

    private enum Page { case running, reached, choose, confirmed }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            let count = model.snapshot.practiceDayStreak(at: now)
            let day = Calendar.current.startOfDay(for: now)
            let today = model.snapshot.practiceDays().contains(day)
            StudyWorkspace {
                VStack(spacing: 20) {
                    switch page {
                    case .running:
                        current(count: displayCount ?? count, today: today)
                        calendar(now: now, today: today, count: count)
                    case .reached:
                        achievement(count: count)
                    case .choose:
                        goals(count: count)
                    case .confirmed:
                        confirmation(count: count)
                    }
                }
            } footer: {
                actions(count: count, today: today)
            }
            .task(id: day) {
                let achievement = achievementID(now: now, count: count, today: today)
                if count >= goal, achievement != lastAchievement {
                    page = .reached
                    lastAchievement = achievement
                    if today { lastAnimatedDay = day.formatted(.iso8601) }
                } else if today, count > 0, lastAnimatedDay != day.formatted(.iso8601) {
                    lastAnimatedDay = day.formatted(.iso8601)
                    if !reduceMotion {
                        displayCount = count - 1
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)) {
                            displayCount = count
                        }
                    }
                }
                model.acknowledgeStreakDay()
            }
            .onChange(of: count) { _, _ in displayCount = nil }
        }
        .navigationTitle("Серия занятий")
        .toolbar { ToolbarItem(placement: .navigation) { StudyBackButton(action: back) } }
    }

    private func achievementID(now: Date, count: Int, today: Bool) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        let offset = today ? 1 - count : -count
        let first = calendar.date(byAdding: .day, value: offset, to: day) ?? day
        return "\(goal)-\(first.timeIntervalSince1970)"
    }

    private func current(count: Int, today: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                StudyGraphic.streakRunning1
                StudyGraphic.streakRunning6
                StudyGraphic.streakRunning2.offset(x: -77, y: -7)
                StudyGraphic.streakRunning3.offset(x: 69, y: -34)
                StudyGraphic.streakRunning4.offset(x: 76, y: 19)
                StudyGraphic.streakRunning5.offset(x: -78, y: 29)
            }.frame(height: 122)
            Text(count, format: .number)
                .font(.custom("Nunito-ExtraBold", size: 74, relativeTo: .largeTitle))
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: false))
                .monospacedDigit()
            Text("\(dayUnit(count)) подряд").font(PlanStyle.title)
            Text(today ? "Ты продлил серию ещё на день." : "Выполни задание сегодня, чтобы продлить серию.")
                .font(PlanStyle.body).padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .foregroundStyle(PlanStyle.reward)
        .background(PlanStyle.rewardBackground, in: RoundedRectangle(cornerRadius: 24))
        .multilineTextAlignment(.center)
    }

    private func calendar(now: Date, today: Bool, count: Int) -> some View {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let first = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let recorded = model.snapshot.practiceDays(calendar: calendar)
        let labels = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Эта неделя").font(PlanStyle.label)
                Spacer()
                Text(today ? "Сегодня засчитано" : "День ещё не засчитан")
                    .font(PlanStyle.caption)
                    .foregroundStyle(today ? PlanStyle.success : PlanStyle.onSoft)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(today ? PlanStyle.successBackground : PlanStyle.soft, in: Capsule())
            }
            HStack(alignment: .top, spacing: 4) {
                ForEach(0..<7) { offset in
                    let date = calendar.date(byAdding: .day, value: offset, to: first) ?? first
                    let active = calendar.isDate(date, inSameDayAs: now)
                    let checked = recorded.contains(calendar.startOfDay(for: date))
                    VStack(spacing: 7) {
                        Text(labels[offset]).font(PlanStyle.label)
                        ZStack {
                            if checked {
                                Circle().fill(PlanStyle.rewardBackground)
                                StudyGraphic.streakRunning7
                            } else if active {
                                Circle().fill(PlanStyle.soft)
                                Circle().fill(PlanStyle.onSoft).frame(width: 6, height: 6)
                            } else {
                                Circle().fill(PlanStyle.subtle)
                            }
                            if active { Circle().strokeBorder(checked ? PlanStyle.reward : PlanStyle.action, lineWidth: 2) }
                        }.frame(width: 42, height: 42)
                        if active { Text("Сегодня").font(PlanStyle.caption) }
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(active ? PlanStyle.onSoft : PlanStyle.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day()))
                    .accessibilityValue(checked ? "Засчитано" : "Ожидает практики")
                }
            }
            Divider()
            targetProgress(count)
        }
        .planCard()
    }

    private func targetProgress(_ count: Int) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(goalRemaining(count))
                    .foregroundStyle(PlanStyle.text)
                Spacer()
                Text("\(min(count, goal)) из \(goal) дней").foregroundStyle(PlanStyle.onSoft)
            }
            .font(PlanStyle.label)
            PlanProgressBar(value: Double(count) / Double(max(1, goal)), height: 8)
        }
    }

    private func goalRemaining(_ count: Int) -> String {
        let remaining = goal - count
        return remaining <= 0 ? "Цель достигнута" : "До цели ещё \(remaining) \(dayUnit(remaining))"
    }

    private func dayUnit(_ count: Int) -> String {
        if (11...14).contains(count % 100) { return "дней" }
        switch count % 10 {
        case 1: return "день"
        case 2...4: return "дня"
        default: return "дней"
        }
    }

    private func achievement(count: Int) -> some View {
        VStack(spacing: 20) {
            reward(badge: "ЦЕЛЬ ДОСТИГНУТА", title: "\(goal) дней подряд!",
                   text: "Хороший старт для привычки заниматься каждый день.", achieved: true)
            HStack(spacing: 16) {
                OnboardingIcon.success.frame(width: 44, height: 44)
                    .background(PlanStyle.successBackground, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Серия продолжается").font(PlanStyle.button)
                    Text("Пройденные дни засчитаются в следующую цель.").font(PlanStyle.caption)
                        .foregroundStyle(PlanStyle.secondary)
                }
            }
            .planCard()
        }
        .padding(.top, 23)
    }

    private func confirmation(count: Int) -> some View {
        VStack(spacing: 20) {
            reward(badge: "НОВАЯ ЦЕЛЬ ПОСТАВЛЕНА", title: "\(goal) дней подряд",
                   text: "Каждый день с практикой продлевает серию.", achieved: false)
            VStack(alignment: .leading, spacing: 13) {
                Text("ТВОЙ ПРОГРЕСС").font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(min(count, goal)) из \(goal) дней").font(PlanStyle.heading)
                    Spacer()
                    Text(goalRemaining(count)).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                }
                PlanProgressBar(value: Double(count) / Double(max(1, goal)), height: 8)
            }.planCard()
        }
        .padding(.top, 23)
    }

    private func reward(badge: String, title: String, text: String, achieved: Bool) -> some View {
        VStack(spacing: 15) {
            ZStack {
                if achieved {
                    StudyGraphic.streakAchieved1
                    Circle().fill(PlanStyle.card).frame(width: 103, height: 103)
                    StudyGraphic.streakAchieved5
                    StudyGraphic.streakAchieved2.offset(x: -107, y: -20)
                    StudyGraphic.streakAchieved3.offset(x: 102, y: -37)
                    StudyGraphic.streakAchieved4.offset(x: 87, y: 46)
                } else {
                    PlanGraphic(.streakGoalOrbits, 244, 154)
                    Circle().fill(PlanStyle.card).frame(width: 103, height: 103)
                    PlanGraphic(.streakGoalCalendar, 56)
                    PlanGraphic(.streakGoalSparkLarge, 22).offset(x: -109, y: -20)
                    PlanGraphic(.streakGoalSparkMedium, 13).offset(x: 102, y: -39)
                    PlanGraphic(.streakGoalSparkSmall, 10).offset(x: 87, y: 46)
                }
            }.frame(height: 148).accessibilityHidden(true)
            Text(badge).font(PlanStyle.caption).padding(.horizontal, 12).padding(.vertical, 6)
                .background(PlanStyle.card, in: Capsule())
            Text(title).font(PlanStyle.display)
            Text(text).font(PlanStyle.body)
        }
        .frame(maxWidth: .infinity, minHeight: 320).padding(18)
        .foregroundStyle(achieved ? PlanStyle.reward : PlanStyle.onSoft)
        .background(achieved ? PlanStyle.rewardBackground : PlanStyle.soft, in: RoundedRectangle(cornerRadius: 24))
        .multilineTextAlignment(.center)
    }

    private func goals(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(count) ДНЕЙ УЖЕ В СЕРИИ").planPill()
            Text("Выбери следующую цель").font(PlanStyle.display)
            Text("Выбери общую длину серии. Пройденные дни уже в зачёте.")
                .font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
            VStack(alignment: .leading, spacing: 15) {
                Text("ПУТЬ К ЦЕЛИ").font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                HStack(spacing: 12) {
                    ForEach([5, 7, 14, 30], id: \.self) { days in
                        VStack(spacing: 7) {
                            Text(days, format: .number).font(PlanStyle.heading)
                            if days <= count { StudyGraphic.streakRunning7 } else { Text("дней").font(PlanStyle.caption) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 65)
                        .background(days <= count ? PlanStyle.rewardBackground : PlanStyle.soft,
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }.planCard()
            ForEach([7, 14, 30], id: \.self) { days in
                StudyChoice(selected: chosen == days) { chosen = days } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(days) дней подряд").font(PlanStyle.label)
                        Text(days <= count ? "Уже пройдено" : "Ещё \(days - count) \(dayUnit(days - count))")
                            .font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                    }
                }.disabled(days <= count)
            }
        }
    }

    private func actions(count: Int, today: Bool) -> some View {
        HStack {
            switch page {
            case .running:
                if !today {
                    Button("К маршруту", action: back).buttonStyle(StudySecondaryStyle())
                    Spacer()
                    StudyAction("Продолжить занятие", action: continueStudy)
                } else {
                    if count >= goal, count < 30 {
                        Button("Выбрать цель") { page = .choose }.buttonStyle(StudySecondaryStyle())
                    }
                    Spacer()
                    StudyAction("К маршруту", action: back)
                }
            case .reached:
                Button("Позже", action: back).buttonStyle(StudySecondaryStyle())
                Spacer()
                if count < 30 { StudyAction("Выбрать цель") { page = .choose } }
                else { StudyAction("К маршруту", action: back) }
            case .choose:
                Button("Назад") { page = .running }.buttonStyle(StudySecondaryStyle())
                Spacer()
                StudyAction("Поставить цель", disabled: chosen == nil) {
                    guard let chosen, chosen > count else { return }
                    goal = chosen
                    page = .confirmed
                }
            case .confirmed:
                Spacer()
                StudyAction("К маршруту", action: back)
            }
        }
    }
}
