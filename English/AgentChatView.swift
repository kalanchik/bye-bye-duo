import SwiftUI

struct AgentChatComposer: View {
    @Binding var text: String
    let prompt: String
    var isSending = false
    var close: (() -> Void)?
    let send: () -> Void

    @FocusState private var focused: Bool
    private var canSend: Bool { !isSending && !text.trimmed.isEmpty }

    var body: some View {
        HStack(spacing: 4) {
            if let close {
                AgentChatIconButton(icon: Image(systemName: "xmark"), size: 12, title: "Свернуть поле", action: close)
            }
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel("Сообщение агенту")
                .accessibilityIdentifier("agent-chat-message")
                .focused($focused)
                .onSubmit { if canSend { send() } }
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(.white, in: Circle())
                    .opacity(canSend ? 1 : 0.45)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Отправить сообщение")
            .help("Отправить сообщение")
            .accessibilityIdentifier("agent-chat-send")
        }
        .padding(.leading, close == nil ? 14 : 0)
        .padding(.trailing, 2)
        .onAppear { focused = true }
    }
}

struct AgentChatIconButton: View {
    let icon: Image
    var size: CGFloat = 22
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            icon.resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.primary.opacity(hovering ? 0.08 : 0), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .help(title)
    }
}

struct AgentChatPanel: View {
    static let width: CGFloat = 440
    static let preferredHeight: CGFloat = 440

    let model: AgentChatModel
    let study: StudyModel
    @Binding var selection: UUID?
    @Binding var drafts: [UUID: String]
    let executablePath: String
    let height: CGFloat
    let newChat: () -> Void
    let close: () -> Void
    let openLesson: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var selectedChat: AgentChat? { model.chats.first { $0.id == selection } }
    private var lessonLinkBackground: Color { Color(white: colorScheme == .dark ? 0.26 : 0.92) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let chat = selectedChat {
                conversation(chat)
                    .id(chat.id)
            } else {
                history
            }
        }
        .frame(width: Self.width, height: height)
        .onExitCommand(perform: close)
    }

    private var header: some View {
        HStack(spacing: 0) {
            if selectedChat != nil {
                AgentChatIconButton(icon: Image(systemName: "chevron.left"), size: 14, title: "История чатов") {
                    selection = nil
                }
                .accessibilityIdentifier("agent-chat-back")
            }
            Text(selectedChat?.title ?? "История чатов")
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, selectedChat == nil ? 16 : 0)
            Spacer(minLength: 6)
            AgentChatIconButton(icon: Image(.agentChatNew), size: 19, title: "Новый чат", action: newChat)
            AgentChatIconButton(icon: Image(systemName: "xmark"), size: 12, title: "Закрыть чаты", action: close)
        }
        .padding(.vertical, 3)
        .padding(.trailing, 4)
    }

    @ViewBuilder
    private var history: some View {
        if model.chats.isEmpty {
            Text(model.storageError ?? "Пока нет чатов")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.chats) { chat in
                        Button { selection = chat.id } label: {
                            HStack(spacing: 12) {
                                Image(.agentChatHistory)
                                    .resizable().scaledToFit()
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chat.title).font(.body.weight(.medium)).lineLimit(1)
                                    Text(model.stages[chat.id]?.rawValue ?? chat.messages.last?.text ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private func conversation(_ chat: AgentChat) -> some View {
        let stage = model.stages[chat.id]
        let canRetry = stage == nil && chat.messages.last?.role == .user
        let draft = Binding(
            get: { drafts[chat.id, default: ""] },
            set: { drafts[chat.id] = $0.isEmpty ? nil : $0 }
        )
        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(chat.messages) { message in
                        messageRow(message)
                    }
                    if let stage {
                        Label {
                            Text(stage.rawValue)
                        } icon: {
                            ProgressView().controlSize(.small)
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    } else if let error = model.errors[chat.id] ?? (canRetry ? "Ответ прервался. Запрос можно повторить." : nil) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.callout).foregroundStyle(.secondary)
                            if canRetry {
                                Button("Повторить запрос") {
                                    model.retry(chat, executablePath: executablePath, study: study)
                                }
                                .accessibilityIdentifier("agent-chat-retry")
                            }
                        }
                    }
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            Divider()
            AgentChatComposer(text: draft, prompt: "Сообщение агенту", isSending: stage != nil) {
                if model.send(draft.wrappedValue, to: chat.id, executablePath: executablePath, study: study) != nil {
                    draft.wrappedValue = ""
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func messageRow(_ message: AgentChat.Message) -> some View {
        if message.role == .user {
            Text(message.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.black)
                .padding(.leading, 44)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                MarkdownText(message.text)
                ForEach(message.lessonIDs, id: \.self) { id in
                    let title = study.snapshot.entries.first { $0.lesson.id == id }?.lesson.title
                    Button { openLesson(id) } label: {
                        Label(title ?? "Открыть занятие", systemImage: "book")
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(PlanStyle.action)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(lessonLinkBackground, in: .rect(cornerRadius: 7))
                            .contentShape(.rect(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AgentChatGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(PlanStyle.card, in: Capsule())
                .overlay { Capsule().strokeBorder(PlanStyle.connector).allowsHitTesting(false) }
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
        }
    }
}
