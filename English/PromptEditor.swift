import AppKit
import SwiftUI

struct PromptEditor: View {
    let kind: TutorPrompt
    let settings: AgentSettings
    let save: (String) throws -> Void

    @State private var expanded = false
    @State private var draft: String?
    @State private var target = PromptTextTarget()
    @State private var error: String?
    @State private var copied: CopyAction?

    private enum CopyAction { case prompt, editingRequest }
    private var current: String { draft ?? settings.template(kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 12) {
                    OnboardingIcon.down
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(kind.title)
                        .font(PlanStyle.heading)
                        .foregroundStyle(PlanStyle.text)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(expanded ? "Развернуто" : "Свернуто")

            if expanded { editorContent }
        }
        .task(id: copied) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copied = nil }
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                PromptTextArea(text: current, editable: draft != nil, target: target) { draft = $0 }
                    .frame(height: 180)
            }
            .background(PlanStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(draft == nil ? PlanStyle.border : PlanStyle.connector)
                    .allowsHitTesting(false)
            }
            Text("Переменные").font(PlanStyle.label)
            WordRows(centered: false, rowSpacing: 4) {
                ForEach(settings.variables) { variable in
                    Button {
                        beginEditing()
                        target.insert(variable.token)
                    } label: {
                        Text(variable.token)
                            .font(PlanStyle.caption.monospaced())
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 9))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PlanStyle.onSoft)
                    .accessibilityLabel("Вставить переменную \(variable.name)")
                    .help("\(variable.token) = \(variable.value)")
                }
            }
            if draft != nil {
                DisclosureGroup("Предпросмотр") {
                    Text((try? settings.render(current)) ?? "Проверь текст и названия переменных.")
                        .font(PlanStyle.body).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let error { Text(error).font(PlanStyle.caption).foregroundStyle(Color(.setupErrorText)) }
        }
        .padding(.vertical, 8)
    }

    private var toolbar: some View {
        HStack(alignment: .top, spacing: 4) {
            WordRows(centered: false, rowSpacing: 0) {
                if let draft {
                    action("Сохранить", symbol: "checkmark") {
                        do {
                            _ = try settings.render(draft)
                            try save(draft)
                            finishEditing()
                        } catch { self.error = error.localizedDescription }
                    }
                    action("Отмена", symbol: "xmark", perform: finishEditing)
                    icon("Вернуть исходный", symbol: "arrow.counterclockwise") {
                        self.draft = kind.original
                        error = nil
                    }
                } else {
                    action("Редактировать", symbol: "pencil") {
                        beginEditing()
                        target.focus()
                    }
                }
                action("Скопировать для редактирования", symbol: "chevron.left.forwardslash.chevron.right") {
                    copy(.editingRequest)
                }
                .foregroundStyle(copied == .editingRequest ? PlanStyle.success : PlanStyle.onSoft)
                .accessibilityValue(copied == .editingRequest ? "Скопировано" : "")
            }
            icon("Скопировать промпт", symbol: copied == .prompt ? "checkmark" : "doc.on.doc") {
                copy(.prompt)
            }
        }
        .padding(8)
        .foregroundStyle(PlanStyle.onSoft)
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(PlanStyle.label)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(PlanStyle.soft, in: RoundedRectangle(cornerRadius: 9))
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func icon(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(title).help(title)
    }

    private func beginEditing() {
        if draft == nil { draft = settings.template(kind) }
        error = nil
    }

    private func finishEditing() {
        draft = nil
        error = nil
        target.clearUndo()
    }

    private func copy(_ action: CopyAction) {
        let contents = action == .prompt ? current : settings.editingRequest(for: kind, template: current)
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(contents, forType: .string) {
            copied = action
        } else {
            error = "Не удалось скопировать текст в буфер обмена."
        }
    }
}

// Keep the same native selection while the toolbar and variable buttons take focus.
private final class PromptTextTarget: NSObject, NSTextViewDelegate {
    weak var view: NSTextView?
    var didChange: ((String) -> Void)?
    private let undo = UndoManager()

    func undoManager(for view: NSTextView) -> UndoManager? { undo }
    func clearUndo() { undo.removeAllActions() }

    func focus() {
        guard let view else { return }
        view.isEditable = true
        view.window?.makeFirstResponder(view)
    }

    func insert(_ token: String) {
        guard let view else { return }
        let range = view.selectedRange()
        focus()
        view.insertText(token, replacementRange: range)
        view.scrollRangeToVisible(view.selectedRange())
    }

    func textDidChange(_ notification: Notification) {
        if let view { didChange?(view.string) }
    }
}

private struct PromptTextArea: NSViewRepresentable {
    let text: String
    let editable: Bool
    let target: PromptTextTarget
    let didChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.font = NSFont(name: "Inter-Regular", size: 16) ?? .systemFont(ofSize: 16)
        view.textColor = NSColor(PlanStyle.text)
        view.insertionPointColor = NSColor(PlanStyle.action)
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.setAccessibilityLabel("Текст промпта")
        view.delegate = target
        target.view = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        target.didChange = didChange
        if view.string != text {
            view.string = text
            target.clearUndo()
        }
        view.isEditable = editable
        view.isSelectable = true
    }
}
