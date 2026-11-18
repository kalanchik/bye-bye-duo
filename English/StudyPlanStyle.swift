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
