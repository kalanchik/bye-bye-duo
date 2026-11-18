import AppKit
import SwiftUI

struct LibraryView: View {
    let model: StudyModel
    @ObservedObject var delegate: EnglishDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selection: String?

    @State private var settingsReturn: String? = "plan"
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if selection == "builder", model.planning.draft != nil {
                PlanBuilderView(model: model, back: { selection = "plan" },
                                open: { selection = "lesson/\($0)" })
            } else if selection == "streak" {
                StreakView(model: model, back: { selection = "plan" }) {
                    if let next = model.nextLesson {
                        selection = "lesson/\(next.id)"
                    } else {
                        selection = "plan"
                    }
                }
            } else if let entry = model.snapshot.entries.first(where: { "lesson/\($0.lesson.id)" == selection }) {
                LessonView(entry: entry, model: model, back: { selection = "plan" },
                           acceptLevel: entry.lesson.levelTest == model.studyLevel ? {
                    model.acceptLevel(from: entry.lesson)
                    if model.studyLevel != entry.lesson.levelTest { selection = "plan" }
                } : nil)
                .id(entry.lesson.id)
            } else {
                library
            }
        }
        .onAppear {
            if selection == "plan", model.planning.draft?.mode == .first, delegate.notificationDestination == nil {
                selection = "builder"
            }
        }
        .onChange(of: selection) { previous, current in
            if current == "settings" { settingsReturn = previous ?? "plan" }
            if current == "plan", previous != "streak",
               let day = model.pendingStreakDay, Calendar.current.isDateInToday(day) {
                selection = "streak"
            }
        }
        .task {
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task {
            await model.configureDailyReminder(enabled: model.dailyReminderEnabled, minutes: model.dailyReminderMinutes)
        }
        .onReceive(delegate.$notificationDestination) { destination in
            if let destination {
                model.refresh()
                selection = destination
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pauseStudy() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            model.pauseStudy()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.pauseStudy()
        }
        .onDisappear { model.pauseStudy() }
        .onAppear {
            let open = openWindow
            delegate.showStudyWindow = { open(id: "study") }
        }
        .alert("English Practice", isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        )) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private var library: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            StudySidebar(model: model, selection: $selection)
                .navigationSplitViewColumnWidth(min: 235, ideal: 236, max: 300)
        } detail: {
            if selection == "settings" {
                PracticeSettings(model: model).navigationTitle("Настройки")
                    .toolbar {
                        ToolbarItem(placement: .navigation) { StudyBackButton { selection = settingsReturn } }
                    }
            } else if selection == "plan" || selection == nil {
                StudyPlanView(model: model, open: { selection = "lesson/\($0)" },
                              openBuilder: { selection = "builder" })
                    .navigationTitle("План обучения")
                    .toolbar {
                        if columnVisibility == .detailOnly {
                            ToolbarItem(placement: .primaryAction) {
                                StudyStreaks(model: model, compact: true, open: { selection = "streak" })
                            }
                        }
                    }
            } else {
                OverviewView(snapshot: model.snapshot, placement: model.learningSetup?.result?.attempt) { selection = "lesson/\($0)" }
                    .navigationTitle("Статистика")
            }
        }
    }
}

private struct StudySidebar: View {
    let model: StudyModel
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        PlanGraphic(.planLogo, 15.6667, 12.7505)
                            .frame(width: 34, height: 34)
                            .background(PlanStyle.action, in: RoundedRectangle(cornerRadius: 11))
                        Text("English Practice")
                            .font(PlanStyle.heading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.92)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.trailing, -12)
                    .padding(.bottom, 36)

                    sidebarHeading("ОБУЧЕНИЕ")
                    VStack(spacing: 6) {
                        navItem("План обучения", icon: .planNavRoute, width: 14.8333, height: 14.8333,
                                destination: "plan", selected: selection == "plan" || selection?.hasPrefix("lesson/") == true)
                        navItem("Статистика", icon: .planNavStats, width: 14.8333, height: 13.1667,
                                destination: "overview", selected: selection == "overview")
                    }

                    PlanStyle.border.frame(height: 1).padding(.horizontal, 4).padding(.vertical, 24)
                    sidebarHeading("ТВОИ СЕРИИ")
                    StudyStreaks(model: model, compact: false, open: { selection = "streak" })
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 16)
            }
            PlanStyle.border.frame(height: 1).padding(.horizontal, 22)
            navItem("Настройки", icon: .planSettings, width: 16, height: 16.5,
                    destination: "settings", selected: selection == "settings")
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(PlanStyle.subtle)
        .foregroundStyle(PlanStyle.text)
    }

    private func sidebarHeading(_ title: String) -> some View {
        Text(title)
            .font(PlanStyle.caption)
            .foregroundStyle(PlanStyle.secondary)
            .padding(.leading, 12)
            .padding(.bottom, 9)
            .accessibilityAddTraits(.isHeader)
    }

    private func navItem(
        _ title: String, icon: ImageResource, width: CGFloat, height: CGFloat, destination: String, selected: Bool
    ) -> some View {
        Button {
            selection = destination
        } label: {
            sidebarLabel(title, icon: icon, width: width, height: height)
                .foregroundStyle(selected ? PlanStyle.onSoft : PlanStyle.text)
                .background(selected ? PlanStyle.soft : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sidebarLabel(_ title: String, icon: ImageResource, width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 12) {
            PlanGraphic(icon, width, height).frame(width: 20)
            Text(title).font(PlanStyle.label)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct StudyStreaks: View {
    let model: StudyModel
    let compact: Bool
    var open: (() -> Void)?

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let days = model.snapshot.practiceDayStreak(at: timeline.date)
            let answers = model.snapshot.correctAnswerStreak
            let layout = compact ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
            layout {
                if let open {
                    Button(action: open) { dayBadge(days) }
                        .buttonStyle(.plain).help("Серия занятий")
                        .accessibilityLabel("Серия занятий, \(days) дней подряд")
                } else {
                    dayBadge(days)
                }
                badge(answers, "верных подряд", icon: .planBolt, width: 14, height: 20,
                      color: PlanStyle.onSoft, background: PlanStyle.soft)
            }
        }
    }

    private func dayBadge(_ days: Int) -> some View {
        badge(days, "дней подряд", icon: .planFlame, width: 15.4246, height: 19.4515,
              color: PlanStyle.reward, background: PlanStyle.rewardBackground)
    }

    private func badge(
        _ count: Int, _ title: String, icon: ImageResource, width: CGFloat, height: CGFloat,
        color: Color, background: Color
    ) -> some View {
        HStack(spacing: compact ? 6 : 10) {
            PlanGraphic(icon, width, height).frame(width: 24)
            let layout = compact ? AnyLayout(HStackLayout(spacing: 5)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
            layout {
                Text(count, format: .number).font(compact ? PlanStyle.label : PlanStyle.heading)
                Text(title).font(PlanStyle.caption)
            }
        }
        .padding(.horizontal, compact ? 8 : 12)
        .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 32 : 58, alignment: .leading)
        .foregroundStyle(color)
        .background(background, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct StudyPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
        }
    }
}

extension View {
    func studyCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary)
            }
    }
}
