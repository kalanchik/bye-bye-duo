import AppKit
import SwiftUI
import UserNotifications

@main
enum EnglishMain {
    static func main() async {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--generate-section",
           let id = UUID(uuidString: CommandLine.arguments[2]) {
            do { try await ChatGeneration.runWorker(id) } catch { exit(1) }
        } else if CommandLine.arguments.dropFirst().first == "--mcp" {
            CourseMCP.run()
        } else {
            PlanStyle.registerFonts()
            EnglishApp.main()
        }
    }
}

struct EnglishApp: App {
    @NSApplicationDelegateAdaptor(EnglishDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage("codexPath") private var codexPath = CodexReviewer.detectedPath
    @State private var selection: String? = "plan"
    @State private var model = StudyModel()
    @State private var agentChat = AgentChatModel()
    @State private var loaded = false
    @State private var showsOnboarding = false
    @State private var lessonAvatar: (route: String, phase: AgentAvatarPhase)?

    private var avatarPhase: AgentAvatarPhase {
        guard !showsOnboarding, let lessonAvatar, lessonAvatar.route == selection else { return .idle }
        return lessonAvatar.phase
    }

    var body: some Scene {
        Window("English Practice", id: "study") {
            ZStack {
                if !loaded {
                    ProgressView()
                } else if showsOnboarding && selection == "settings" {
                    PracticeSettings(model: model)
                        .navigationTitle("Настройки")
                        .task {
                            if model.dailyReminderEnabled && model.dailyReminderStatus == .off {
                                await model.configureDailyReminder(enabled: true, minutes: model.dailyReminderMinutes,
                                                                   goalMinutes: model.learningSetup?.goalMinutes)
                            }
                        }
                        .toolbar {
                            ToolbarItem(placement: .navigation) { StudyBackButton { selection = "plan" } }
                        }
                } else if showsOnboarding {
                    OnboardingView(model: model) { showsOnboarding = false }
                        .toolbar(removing: .title)
                } else {
                    LibraryView(model: model, delegate: delegate, selection: $selection) { lessonID, phase in
                        let route = "lesson/\(lessonID)"
                        if selection == route { lessonAvatar = (route, phase) }
                    }
                }
            }
            .frame(minWidth: 850, minHeight: 580)
            .overlay {
                FloatingAgentAvatar(phase: avatarPhase, chats: agentChat, study: model,
                                    executablePath: codexPath.trimmed) { lessonID in
                    showsOnboarding = false
                    selection = "lesson/\(lessonID)"
                }
            }
            .task {
                guard !loaded else { return }
                model.refresh()
                agentChat.load(executablePath: codexPath.trimmed, study: model)
                showsOnboarding = model.shouldPresentOnboarding && delegate.notificationDestination == nil
                loaded = true
            }
            .onReceive(delegate.$notificationDestination) { destination in
                if destination != nil { showsOnboarding = false }
            }
        }
        .defaultSize(width: 1200, height: 820)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Настройки…") {
                    selection = "settings"
                    openWindow(id: "study")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                if showsOnboarding {
                    Button("Вернуться к плану") { showsOnboarding = false }
                } else if loaded && model.learningSetup?.stage != .complete {
                    Button("Настроить обучение…") { selection = "plan"; showsOnboarding = true }
                }
            }
        }
    }
}

final class EnglishDelegate: NSObject, NSApplicationDelegate, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var notificationDestination: String?
    var showStudyWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let destination: String? = if info["openStudyPlan"] as? Bool == true {
            "plan"
        } else if let lessonID = info["lessonId"] as? String {
            "lesson/\(lessonID)"
        } else {
            nil
        }
        await MainActor.run {
            guard let destination else { return }
            notificationDestination = destination
            showStudyWindow?()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

struct PracticeSettings: View {
    let model: StudyModel

    @AppStorage("codexPath") private var codexPath = CodexReviewer.detectedPath
    @AppStorage(PracticeVoice.preferenceKey) private var voice = PracticeVoice.defaultVoice
    @State private var preview = PracticeSpeech()
    @State private var previewError: String?

    var body: some View {
        StudyPage {
            VStack(alignment: .leading, spacing: 16) {
                Text("Озвучка").font(PlanStyle.heading).accessibilityAddTraits(.isHeader)
                StudySegments("Голос", options: [PracticeVoice.male, .female], selection: $voice) {
                    $0 == .male ? "Мужской" : "Женский"
                }
                Button {
                    if preview.isPlaying { preview.stop() }
                    else {
                        previewError = nil
                        preview.play("The bus leaves at half past seven.", voice: voice) { previewError = $0 }
                    }
                } label: {
                    Label(preview.isPlaying ? "Остановить пример" : "Прослушать пример",
                          systemImage: preview.isPlaying ? "stop.fill" : "speaker.wave.2")
                }
                .buttonStyle(StudySecondaryStyle())
                if let previewError {
                    Text(previewError).font(PlanStyle.caption).foregroundStyle(Color(.setupErrorText))
                }
            }
            .planCard(padding: 24)

            AgentAvatarSettingsView()

            AgentSettingsView(model: model, executablePath: codexPath.trimmed)

            DailyReminderView(model: model)

            VStack(alignment: .leading, spacing: 16) {
                Text("Подключение Codex").font(PlanStyle.heading).accessibilityAddTraits(.isHeader)
                Text("Генерация и проверка используют твой аккаунт Codex CLI.")
                    .font(PlanStyle.body).foregroundStyle(PlanStyle.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Путь к Codex CLI").font(PlanStyle.label)
                    TextField("/usr/local/bin/codex", text: $codexPath)
                        .accessibilityLabel("Путь к Codex CLI")
                        .textFieldStyle(.plain).font(PlanStyle.body)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(PlanStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PlanStyle.connector).allowsHitTesting(false) }
                    let found = FileManager.default.isExecutableFile(atPath: codexPath.trimmed)
                    Label(found ? "Исполняемый файл найден" : "Исполняемый файл не найден",
                          systemImage: found ? "checkmark.circle" : "exclamationmark.circle")
                        .font(PlanStyle.caption).foregroundStyle(found ? PlanStyle.success : Color(.setupErrorText))
                }
                Button("Определить автоматически") { codexPath = CodexReviewer.detectedPath }
                    .buttonStyle(StudySecondaryStyle())
            }
            .planCard(padding: 24)
        }
        .foregroundStyle(PlanStyle.text)
        .background(PlanStyle.canvas)
        .onChange(of: voice) { _, _ in
            preview.stop()
            previewError = nil
        }
        .onDisappear { preview.stop() }
    }
}

private struct DailyReminderView: View {
    let model: StudyModel
    @State private var timeText = ""
    @State private var showsTimeError = false
    @FocusState private var timeFocused: Bool

    private var status: String {
        if model.configuringDailyReminder { return "Настраиваем…" }
        switch model.dailyReminderStatus {
        case .off: return "Выключено"
        case .scheduled: return "Включено"
        case .needsPermission: return "Разреши уведомления в настройках macOS"
        case .failed: return "macOS не удалось назначить напоминание. Можно повторить."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Ежедневное напоминание")
            } icon: {
                OnboardingIcon.bell
            }
            .font(PlanStyle.heading)
            .accessibilityAddTraits(.isHeader)

            HStack(spacing: 12) {
                Text("Время").font(PlanStyle.label)
                TextField("ЧЧ:ММ", text: $timeText)
                    .accessibilityLabel("Время напоминания")
                    .textFieldStyle(.plain)
                    .font(PlanStyle.body.monospacedDigit())
                    .padding(.horizontal, 12)
                    .frame(width: 108, height: 44)
                    .background(PlanStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(showsTimeError ? Color(.setupErrorText) : timeFocused ? Color(.setupFocus) : PlanStyle.connector,
                                          lineWidth: timeFocused ? 2 : 1)
                            .allowsHitTesting(false)
                    }
                    .focused($timeFocused)
                    .onChange(of: timeText) { showsTimeError = false }
                    .onSubmit(saveTime)
            }
            if showsTimeError {
                Text("Введи время от 00:00 до 23:59, например 9:30.")
                    .font(PlanStyle.caption).foregroundStyle(Color(.setupErrorText))
            }
            Text(status).font(PlanStyle.caption).foregroundStyle(PlanStyle.secondary)

            HStack(spacing: 12) {
                if model.dailyReminderEnabled {
                    Button("Выключить") {
                        Task { await model.configureDailyReminder(enabled: false, minutes: model.dailyReminderMinutes) }
                    }
                    .buttonStyle(StudySecondaryStyle())
                }
                Button(model.dailyReminderEnabled ? "Сохранить время" : "Включить", action: saveTime)
                    .buttonStyle(PlanPrimaryButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .disabled(model.configuringDailyReminder)
        .planCard(padding: 24)
        .onChange(of: model.dailyReminderMinutes, initial: true) { _, minutes in
            timeText = ReminderTime.text(for: minutes)
        }
    }

    private func saveTime() {
        guard let minutes = ReminderTime.minutes(from: timeText) else {
            showsTimeError = true
            timeFocused = true
            return
        }
        timeText = ReminderTime.text(for: minutes)
        timeFocused = false
        Task { await model.configureDailyReminder(enabled: true, minutes: minutes) }
    }
}
