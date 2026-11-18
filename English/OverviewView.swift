import Charts
import SwiftUI

struct OverviewView: View {
    let snapshot: CourseSnapshot
    let placement: Attempt?
    let open: (String) -> Void

    private enum Tab: String, CaseIterable { case study = "Обучение", agent = "Агент" }
    @State private var tab = Tab.study
    @State private var period = ActivityPeriod.week

    var body: some View {
        StudyPage {
            StudySegments("Раздел статистики", options: Tab.allCases, selection: $tab) { $0.rawValue }
            switch tab {
            case .study:
                TimelineView(.everyMinute) { _ in
                    ActivityChart(bins: snapshot.activity(period, placement: placement), period: $period)
                }
                courseSummary
                homework
                topics
            case .agent:
                AgentStatisticsView(usage: snapshot.agentUsage)
            }
        }
        .foregroundStyle(PlanStyle.text)
        .background(PlanStyle.canvas)
    }

    private var courseSummary: some View {
        let completed = snapshot.entries.count { entry in
            let attempts = snapshot.progress[entry.lesson.id]?.attempts ?? []
            return entry.lesson.isCheckpoint ? attempts.contains(where: entry.lesson.passed) : !attempts.isEmpty
        }
        let first = snapshot.progress.values.flatMap { $0.attempts.first?.feedback ?? [] }
        let wrong = snapshot.progress.values.flatMap(\.attempts).flatMap(\.feedback).count { !$0.correct }
        return VStack(alignment: .leading, spacing: 12) {
            Text("За всё время").font(PlanStyle.heading).accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 16) {
                StatisticValue("Уроки и работы", "\(completed) из \(snapshot.entries.count)")
                StatisticValue("Верно с первой попытки", first.isEmpty ? "—" : "\(first.count(where: \.correct)) из \(first.count)")
                StatisticValue("Ошибки в попытках", "\(wrong)")
            }
        }.planCard(padding: 20)
    }

    @ViewBuilder private var homework: some View {
        let pending = snapshot.entries.filter { $0.lesson.kind == .homework && snapshot.progress[$0.lesson.id]?.finished != true }
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Домашние задания").font(PlanStyle.heading).accessibilityAddTraits(.isHeader)
                ForEach(pending, id: \.lesson.id) { entry in
                    Button { open(entry.lesson.id) } label: {
                        HStack(spacing: 12) {
                            PlanGraphic(.planPencil, 18)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.lesson.title).font(PlanStyle.label)
                                Text(entry.section.title).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                            }
                            Spacer(minLength: 8)
                            if let due = snapshot.progress[entry.lesson.id]?.dueAt {
                                Text(due.formatted(.dateTime.day().month().hour().minute().locale(.init(identifier: "ru"))))
                                    .font(PlanStyle.caption)
                                    .foregroundStyle(due < .now ? Color(.setupErrorText) : PlanStyle.secondary)
                            }
                            Image(systemName: "chevron.right").foregroundStyle(PlanStyle.secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 6).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.planCard(padding: 20)
        }
    }

    private var topics: some View {
        var counts: [String: Int] = [:]
        for entry in snapshot.entries {
            for attempt in snapshot.progress[entry.lesson.id]?.attempts ?? [] {
                let exercises = entry.lesson.includingVocabulary(attempt.vocabularyCards ?? []).exercises
                let names = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0.topic ?? entry.section.title) })
                for answer in attempt.feedback where !answer.correct {
                    counts[names[answer.id] ?? entry.section.title, default: 0] += 1
                }
            }
        }
        let sorted = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Темы для повторения").font(PlanStyle.heading).accessibilityAddTraits(.isHeader)
            if sorted.isEmpty {
                Text("Здесь появятся темы, в которых были ошибки.").font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
            } else {
                ForEach(sorted.prefix(5), id: \.key) { topic in
                    HStack {
                        Text(topic.key).font(PlanStyle.body)
                        Spacer()
                        Text(topic.value, format: .number).font(PlanStyle.label.monospacedDigit())
                    }.accessibilityElement(children: .combine)
                }
            }
        }.planCard(padding: 20)
    }
}

private struct StatisticValue: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(PlanStyle.heading.monospacedDigit())
            Text(label).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private struct ActivityChart: View {
    let bins: [ActivityBin]
    @Binding var period: ActivityPeriod

    private var dateStyle: Date.FormatStyle { .dateTime.day().month(.abbreviated).locale(.init(identifier: "ru")) }
    private var tick: Int { max(1, Int(ceil(Double(bins.map(\.count).max() ?? 0) / 3))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack { heading; Spacer(minLength: 16); picker }
                VStack(alignment: .leading, spacing: 8) { heading; picker }
            }
            let total = bins.reduce(0) { $0 + $1.count }
            Text("Проверено за период · \(total)").font(PlanStyle.label).foregroundStyle(PlanStyle.onSoft)
            Chart(Array(bins.enumerated()), id: \.element.id) { index, bin in
                RectangleMark(xStart: .value("Начало", Double(index) - 0.32),
                              xEnd: .value("Конец", Double(index) + 0.32),
                              yStart: .value("Основание", 0), yEnd: .value("Проверено", bin.count))
                    .foregroundStyle(PlanStyle.action)
                    .cornerRadius(3)
                    .accessibilityLabel(bin.start == bin.end ? bin.start.formatted(dateStyle)
                                        : "\(bin.start.formatted(dateStyle)) – \(bin.end.formatted(dateStyle))")
                    .accessibilityValue("\(bin.count)")
            }
            .chartYScale(domain: 0...(tick * 3))
            .chartXScale(domain: -0.5...(Double(max(1, bins.count)) - 0.5))
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(stride(from: 0, through: tick * 3, by: tick))) {
                    AxisGridLine().foregroundStyle(PlanStyle.border)
                    AxisValueLabel().font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, bins.count / 3, 2 * bins.count / 3, bins.count - 1]) { value in
                    if let index = value.as(Int.self), bins.indices.contains(index) {
                        AxisValueLabel(centered: false, anchor: .top) {
                            Text(bins[index].start.formatted(dateStyle)).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                        }
                    }
                }
            }
            .frame(height: 170)
            .accessibilityLabel("Выполненные задания за \(period.title)")
            if total == 0 {
                Text("За этот период пока нет проверенных заданий.").font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            } else if period == .quarter {
                Text("Один столбец — до семи дней практики.").font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            }
        }
        .planCard(padding: 20)
    }

    private var heading: some View {
        Text("Выполненные задания").font(PlanStyle.heading).fixedSize().accessibilityAddTraits(.isHeader)
    }
    private var picker: some View {
        StudySegments("Период графика", options: ActivityPeriod.allCases, selection: $period) { $0.title }
    }
}

private struct AgentStatisticsView: View {
    let usage: [AgentUsage]
    private func total(_ key: KeyPath<AgentUsage, Int>) -> Int { usage.reduce(0) { $0 + $1[keyPath: key] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Использование Codex").font(PlanStyle.heading).accessibilityAddTraits(.isHeader)
            Text("Запросы из English Practice за всё время учёта.").font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
            HStack(alignment: .top, spacing: 16) {
                StatisticValue("Запросы", total(\.requests).formatted())
                StatisticValue("Токены", total(\.measured) == 0 ? "—" : total(\.total).formatted())
            }
            if total(\.measured) > 0 {
                Text("Входящие · \(total(\.input).formatted())     Исходящие · \(total(\.output).formatted())")
                    .font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            }
            if total(\.measured) < total(\.requests) {
                Text("Codex сообщил расход для \(total(\.measured)) из \(total(\.requests)) запросов.")
                    .font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
            }
        }.planCard(padding: 20)

        VStack(alignment: .leading, spacing: 16) {
            Text("По назначению").font(PlanStyle.heading).accessibilityAddTraits(.isHeader)
            if usage.isEmpty {
                Text("Здесь появятся новые запросы на проверку ответов и подготовку материалов.")
                    .font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow {
                        Text("Назначение")
                        Text("Запросы").gridColumnAlignment(.trailing)
                        Text("Токены").gridColumnAlignment(.trailing)
                    }.font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)
                    ForEach(AgentPurpose.allCases, id: \.self) { purpose in
                        if let row = usage.first(where: { $0.purpose == purpose }) {
                            GridRow {
                                Text(purpose.title).frame(maxWidth: .infinity, alignment: .leading)
                                Text(row.requests.formatted())
                                Text(row.measured == 0 ? "—" : row.total.formatted())
                            }.font(PlanStyle.label.monospacedDigit()).accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }.planCard(padding: 20)
    }
}
