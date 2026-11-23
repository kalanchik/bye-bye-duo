import SwiftUI

struct FloatingAgentAvatar: View {
    private static let dragThreshold: CGFloat = 5
    private static let panelTop: CGFloat = 38
    private static let panelHeight: CGFloat = 46
    private static let statusHeight: CGFloat = 56
    private static let statusGap: CGFloat = 8
    private static let margin: CGFloat = 12

    let phase: AgentAvatarPhase
    let chats: AgentChatModel
    let study: StudyModel
    let executablePath: String
    let openLesson: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("agentAvatarCorner") private var corner = AvatarCorner.bottomRight
    @GestureState private var drag: AvatarDrag?
    @State private var displayedCenter: CGPoint?
    @State private var avatarHovered = false
    @State private var actionsHovered = false
    @State private var hoverRevealsActions = false
    @State private var pinnedActions = false
    @State private var showsComposer = false
    @State private var showsChat = false
    @State private var selectedChat: UUID?
    @State private var draft = ""
    @State private var chatDrafts: [UUID: String] = [:]
    @State private var sendError: String?
    private var preferences = AgentAvatarPreferences()

    private var isHovering: Bool { avatarHovered || actionsHovered }

    var body: some View {
        GeometryReader { proxy in
            let active = chats.activeChat
            let status = active.flatMap { chats.stages[$0.id] }
            let bottom = Self.panelTop + Self.panelHeight + Self.margin
                + (status == nil ? 0 : Self.statusGap + Self.statusHeight)
            let bounds = AvatarBounds(size: proxy.size, avatarSize: AgentAvatar.size, bottomClearance: bottom)
            let anchor = bounds.center(for: corner)
            let center = drag.map { bounds.clamp($0.center) } ?? anchor
            let actionsVisible = drag == nil && (hoverRevealsActions || pinnedActions || showsComposer || showsChat || status != nil)
            let popoverX = bounds.panelCenter(anchor.x, width: AgentChatPanel.width, margin: Self.margin)
            let popoverAnchor = CGRect(x: popoverX, y: anchor.y - AgentAvatar.size.height / 2,
                                       width: 1, height: AgentAvatar.size.height)
            let room = corner.isBottom ? popoverAnchor.minY : proxy.size.height - popoverAnchor.maxY
            let chatHeight = min(AgentChatPanel.preferredHeight, max(250, room - 2 * Self.margin))

            ZStack {
                avatar(status: status, bounds: bounds, anchor: anchor)
                    .position(center)

                if actionsVisible {
                    let width: CGFloat = showsComposer ? 360 : 100
                    actions
                        .frame(width: width, height: Self.panelHeight)
                        .modifier(AgentChatGlass())
                        .contentShape(Capsule())
                        .onHover { actionsHovered = $0 }
                        .position(x: bounds.panelCenter(center.x, width: width, margin: Self.margin),
                                  y: center.y + Self.panelTop + Self.panelHeight / 2)
                        .transition(panelTransition)
                }

                if drag == nil, let active, let status {
                    let width: CGFloat = 330
                    statusButton(active, stage: status)
                        .frame(width: width, height: Self.statusHeight)
                        .modifier(AgentChatGlass())
                        .contentShape(Capsule())
                        .position(x: bounds.panelCenter(center.x, width: width, margin: Self.margin),
                                  y: center.y + Self.panelTop + Self.panelHeight + Self.statusGap + Self.statusHeight / 2)
                        .transition(panelTransition)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: actionsVisible)
            .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: showsComposer)
            .animation(drag == nil && !reduceMotion ? .smooth(duration: 0.30) : nil, value: center)
            .popover(isPresented: $showsChat, attachmentAnchor: .rect(.rect(popoverAnchor)),
                     arrowEdge: corner.isBottom ? .bottom : .top) {
                AgentChatPanel(model: chats, study: study, selection: $selectedChat, drafts: $chatDrafts,
                               executablePath: executablePath, height: chatHeight, newChat: startChat,
                               close: { showsChat = false }) { id in
                    showsChat = false
                    pinnedActions = false
                    openLesson(id)
                }
            }
        }
        .coordinateSpace(.named(DragSpace.window))
        .task(id: isHovering) {
            if isHovering {
                hoverRevealsActions = true
            } else {
                do { try await Task.sleep(for: .milliseconds(170)) } catch { return }
                hoverRevealsActions = false
            }
        }
        .onChange(of: drag != nil) { _, moving in
            if moving { actionsHovered = false }
        }
    }

    private var panelTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -5))
    }

    private func avatar(status: AgentChatModel.Stage?, bounds: AvatarBounds, anchor: CGPoint) -> some View {
        AgentAvatar(phase: status == nil ? phase : .thinking, shape: preferences.shape, tint: preferences.tint,
                    isComposing: showsComposer, activate: toggleActions)
            .help("Открой действия чата или перетащи аватар в другой угол")
            .accessibilityValue("\(status?.rawValue ?? phase.accessibilityValue), \(corner.title)")
            .accessibilityIdentifier("floating-agent-avatar")
            .accessibilityActions {
                Button("Новый чат", action: startChat)
                Button("История чатов") { openChat(nil) }
                ForEach(AvatarCorner.allCases.filter { $0 != corner }, id: \.self) { destination in
                    Button("Переместить в \(destination.title)") { corner = destination }
                }
            }
            .onHover { avatarHovered = $0 }
            .onGeometryChange(for: CGPoint.self) { geometry in
                let frame = geometry.frame(in: .named(DragSpace.window))
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: { displayedCenter = $0 }
            .highPriorityGesture(dragGesture(in: bounds, from: anchor))
            .alert("Не удалось начать чат", isPresented: Binding(
                get: { sendError != nil }, set: { if !$0 { sendError = nil } }
            )) {
                Button("OK", role: .cancel) { sendError = nil }
            } message: {
                Text(sendError ?? "")
            }
    }

    @ViewBuilder
    private var actions: some View {
        if showsComposer {
            AgentChatComposer(text: $draft, prompt: "Начать новый чат", close: closeComposer) {
                if let id = chats.send(draft, to: nil, executablePath: executablePath, study: study) {
                    draft = ""
                    openChat(id)
                } else {
                    sendError = chats.storageError
                }
            }
            .onExitCommand(perform: closeComposer)
            .transition(.opacity)
        } else {
            HStack(spacing: 3) {
                AgentChatIconButton(icon: Image(.agentChatNew), title: "Новый чат", action: startChat)
                    .accessibilityIdentifier("avatar-new-chat")
                Divider().frame(height: 20)
                AgentChatIconButton(icon: Image(.agentChatHistory), title: "История чатов") { openChat(nil) }
                    .accessibilityIdentifier("avatar-chat-history")
            }
            .transition(.opacity)
        }
    }

    private func statusButton(_ chat: AgentChat, stage: AgentChatModel.Stage) -> some View {
        Button { openChat(chat.id) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(stage.rawValue).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 17)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Открыть чат")
        .accessibilityIdentifier("avatar-chat-status")
    }

    private func toggleActions() {
        if showsComposer {
            closeComposer()
        } else {
            pinnedActions.toggle()
        }
    }

    private func startChat() {
        showsChat = false
        showsComposer = true
    }

    private func closeComposer() {
        showsComposer = false
        pinnedActions = false
    }

    private func openChat(_ id: UUID?) {
        selectedChat = id
        showsComposer = false
        showsChat = true
    }

    private func dragGesture(in bounds: AvatarBounds, from anchor: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: Self.dragThreshold, coordinateSpace: .named(DragSpace.window))
            .updating($drag) { value, drag, transaction in
                // Use the visible frame if the avatar is grabbed before it finishes snapping.
                let start = drag?.start ?? displayedCenter ?? anchor
                let center = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                drag = AvatarDrag(start: start, center: center)
                transaction.animation = nil
            }
            .onEnded { value in
                guard hypot(value.translation.width, value.translation.height) >= Self.dragThreshold else { return }
                corner = bounds.nearestCorner(to: value.location, keeping: corner)
            }
    }

    private nonisolated enum DragSpace: Hashable { case window }

    private struct AvatarDrag {
        let start: CGPoint
        let center: CGPoint
    }
}

private nonisolated enum AvatarCorner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isRight: Bool { self == .topRight || self == .bottomRight }
    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }

    var title: String {
        switch self {
        case .topLeft: "левый верхний угол"
        case .topRight: "правый верхний угол"
        case .bottomLeft: "левый нижний угол"
        case .bottomRight: "правый нижний угол"
        }
    }
}

private nonisolated struct AvatarBounds {
    let size: CGSize
    let avatarSize: CGSize
    let bottomClearance: CGFloat

    private var horizontalInset: CGFloat { min(size.width / 2, 12 + avatarSize.width / 2) }
    private var topInset: CGFloat { min(size.height / 2, 12 + avatarSize.height / 2) }
    private var bottomInset: CGFloat { min(size.height / 2, bottomClearance) }

    func center(for corner: AvatarCorner) -> CGPoint {
        CGPoint(x: corner.isRight ? size.width - horizontalInset : horizontalInset,
                y: corner.isBottom ? size.height - bottomInset : topInset)
    }

    func clamp(_ center: CGPoint) -> CGPoint {
        CGPoint(x: min(size.width - horizontalInset, max(horizontalInset, center.x)),
                y: min(size.height - bottomInset, max(topInset, center.y)))
    }

    func panelCenter(_ x: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        let inset = min(size.width / 2, width / 2 + margin)
        return min(size.width - inset, max(inset, x))
    }

    func nearestCorner(to point: CGPoint, keeping current: AvatarCorner) -> AvatarCorner {
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        let right = point.x == middle.x ? current.isRight : point.x > middle.x
        let bottom = point.y == middle.y ? current.isBottom : point.y > middle.y
        switch (right, bottom) {
        case (false, false): return .topLeft
        case (true, false): return .topRight
        case (false, true): return .bottomLeft
        case (true, true): return .bottomRight
        }
    }
}
