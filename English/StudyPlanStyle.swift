import CoreText
import SwiftUI

enum PlanStyle {
    static let canvas = Color(.planCanvas)
    static let card = Color(.planCard)
    static let subtle = Color(.planSubtle)
    static let text = Color(.planText)
    static let secondary = Color(.planSecondary)
    static let border = Color(.planBorder)
    static let action = Color(.planAction)
    static let actionEdge = Color(.planActionEdge)
    static let onAction = Color(.planOnAction)
    static let soft = Color(.planSoft)
    static let onSoft = Color(.planOnSoft)
    static let success = Color(.planSuccess)
    static let successBackground = Color(.planSuccessBackground)
    static let reward = Color(.planReward)
    static let rewardBackground = Color(.planRewardBackground)
    static let connector = Color(.planConnector)

    static func registerFonts() {
        _ = registeredFonts
    }

    private static let registeredFonts: Void = {
        for name in ["Nunito-ExtraBold", "Inter-Regular", "Inter-Medium", "Inter-SemiBold"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "PlanFonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    static let display = Font.custom("Nunito-ExtraBold", size: 36, relativeTo: .largeTitle)
    static let title = Font.custom("Nunito-ExtraBold", size: 28, relativeTo: .title)
    static let heading = Font.custom("Nunito-ExtraBold", size: 22, relativeTo: .title2)
    static let caption = Font.custom("Inter-Regular", size: 13, relativeTo: .caption)
    static let label = Font.custom("Inter-SemiBold", size: 14, relativeTo: .subheadline)
    static let button = Font.custom("Inter-SemiBold", size: 16, relativeTo: .body)
    static let body = Font.custom("Inter-Regular", size: 16, relativeTo: .body)
    static let answer = Font.custom("Inter-Medium", size: 17, relativeTo: .body)
    static let prompt = Font.custom("Inter-SemiBold", size: 24, relativeTo: .title2)
}

struct PlanGraphic: View {
    let resource: ImageResource
    let width: CGFloat
    let height: CGFloat
    var tint: Color?

    init(_ resource: ImageResource, _ width: CGFloat, _ height: CGFloat? = nil, tint: Color? = nil) {
        self.resource = resource
        self.width = width
        self.height = height ?? width
        self.tint = tint
    }

    var body: some View {
        Image(resource)
            .renderingMode(tint == nil ? .original : .template)
            .resizable()
            .frame(width: width, height: height)
            .foregroundStyle(tint ?? .primary)
            .accessibilityHidden(true)
    }
}

struct PlanProgressBar: View {
    let value: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(Color(.planTrack))
                .overlay(alignment: .leading) {
                    Capsule().fill(Color(.planFill))
                        .frame(width: proxy.size.width * min(1, max(0, value)))
                }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct PlanPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        configuration.label
            .font(PlanStyle.button)
            .foregroundStyle(isEnabled ? PlanStyle.onAction : Color(.setupOnDisabled))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                if isEnabled {
                    shape.fill(PlanStyle.actionEdge)
                    shape.fill(PlanStyle.action)
                        .padding(.bottom, configuration.isPressed ? 0 : 3)
                } else {
                    shape.fill(Color(.setupDisabled))
                }
            }
            .contentShape(shape)
    }
}

extension View {
    func planCard(padding: CGFloat = 16, radius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PlanStyle.card, in: shape)
            .overlay { shape.strokeBorder(PlanStyle.border).allowsHitTesting(false) }
    }

    func planPill(background: Color = PlanStyle.soft) -> some View {
        font(PlanStyle.caption)
            .foregroundStyle(PlanStyle.onSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
    }
}

struct StudySegments<Option: Hashable>: View {
    let label: String
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    init(_ label: String, options: [Option], selection: Binding<Option>, title: @escaping (Option) -> String) {
        self.label = label
        self.options = options
        self._selection = selection
        self.title = title
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = selection == option
                Button { selection = option } label: {
                    Text(title(option))
                        .font(PlanStyle.label)
                        .foregroundStyle(selected ? PlanStyle.onSoft : PlanStyle.secondary)
                        .padding(.horizontal, 14).frame(minWidth: 44, minHeight: 44)
                        .background(selected ? PlanStyle.soft : .clear, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(PlanStyle.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(PlanStyle.border).allowsHitTesting(false) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

struct SetupOutlineButtonStyle: ButtonStyle {
    var width: CGFloat?
    let height: CGFloat
    let radius: CGFloat
    var selected = false
    var control = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        configuration.label
            .padding(.horizontal, width == nil ? 12 : 0)
            .padding(.vertical, width == nil ? 6 : 0)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: height)
            .frame(width: width)
            .background(selected || configuration.isPressed ? PlanStyle.soft : PlanStyle.card, in: shape)
            .overlay {
                shape.strokeBorder(selected ? PlanStyle.action : (control ? PlanStyle.connector : PlanStyle.border),
                                   lineWidth: selected ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
    }
}

struct StudyDropdown: View {
    struct Option: Identifiable {
        let id: String
        let title: String
    }

    let label: String
    let options: [Option]
    let selected: String
    let select: (String) -> Void

    @State private var expanded = false
    @State private var fieldWidth: CGFloat = 320
    @State private var hovered: String?
    @FocusState private var focused: String?

    private var value: String { options.first { $0.id == selected }?.title ?? selected }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(PlanStyle.label).accessibilityHidden(true)
            Button { expanded.toggle() } label: {
                HStack(spacing: 12) {
                    Text(value).font(PlanStyle.button).foregroundStyle(PlanStyle.text)
                    Spacer(minLength: 8)
                    OnboardingIcon.down.rotationEffect(.degrees(expanded ? 180 : 0)).frame(width: 24)
                }
            }
            .buttonStyle(SetupOutlineButtonStyle(height: 44, radius: 12, selected: expanded, control: true))
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .disabled(options.isEmpty)
            .onKeyPress(.downArrow) { expanded = true; return .handled }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { fieldWidth = $0 }
            .popover(isPresented: $expanded, arrowEdge: .bottom) { menu }
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var menu: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(options) { option in
                        let active = option.id == selected
                        Button { choose(option.id) } label: {
                            HStack(spacing: 12) {
                                Text(option.title).font(PlanStyle.label)
                                Spacer(minLength: 8)
                                if active { OnboardingIcon.menuCheck.frame(width: 22) }
                            }
                            .foregroundStyle(active ? PlanStyle.onSoft : PlanStyle.text)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(active ? PlanStyle.soft : hovered == option.id ? PlanStyle.subtle : .clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focused($focused, equals: option.id)
                        .accessibilityAddTraits(active ? .isSelected : [])
                        .onHover { inside in
                            if inside { hovered = option.id }
                            else if hovered == option.id { hovered = nil }
                        }
                        .id(option.id)
                    }
                }
                .padding(8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: fieldWidth, height: min(CGFloat(options.count) * 46 + 14, 322))
            .background(PlanStyle.card)
            .onAppear {
                hovered = nil
                focused = options.contains { $0.id == selected } ? selected : options.first?.id
                if let focused { proxy.scrollTo(focused) }
            }
            .onChange(of: focused) { _, id in if let id { proxy.scrollTo(id) } }
            .onKeyPress(.downArrow) { moveFocus(by: 1); return .handled }
            .onKeyPress(.upArrow) { moveFocus(by: -1); return .handled }
            .onKeyPress(.return) {
                guard let focused else { return .ignored }
                choose(focused)
                return .handled
            }
            .onExitCommand { expanded = false }
        }
    }

    private func moveFocus(by offset: Int) {
        guard !options.isEmpty else { return }
        let index = options.firstIndex { $0.id == focused } ?? 0
        focused = options[min(max(0, index + offset), options.count - 1)].id
    }

    private func choose(_ id: String) {
        expanded = false
        if id != selected { select(id) }
    }
}
