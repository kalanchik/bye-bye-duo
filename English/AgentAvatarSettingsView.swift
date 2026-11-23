import SwiftUI

struct AgentAvatarSettingsView: View {
    @Environment(\.self) private var environment
    @AppStorage("agentAvatarCustomColors") private var savedCustomColors = ""
    private var preferences = AgentAvatarPreferences()
    @State private var showsColorPicker = false

    private let shapeColumns = [GridItem(.adaptive(minimum: 108), spacing: 8)]
    private let colorColumns = [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 4)]
    private static let palette = BlobAvatarCatalog.bundled.palette
    private static let presetValues = Set(palette.compactMap { $0.tint?.rawValue })

    private var customColors: [Int] {
        savedCustomColors.split(separator: ",").compactMap { Int($0) }.filter { (0...0xFFFFFF).contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Аватар агента").font(PlanStyle.heading).accessibilityAddTraits(.isHeader)
                Spacer()
                AgentAvatar.thumbnail(shape: preferences.shape, tint: preferences.tint, background: PlanStyle.card)
                    .frame(width: 80, height: 64)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Предпросмотр аватара")
                    .accessibilityValue(preferences.shape.title)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("avatar-settings-preview")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Форма").font(PlanStyle.label)
                LazyVGrid(columns: shapeColumns, spacing: 8) {
                    ForEach(AgentAvatarShape.allCases) { shape in
                        shapeButton(shape)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Формы аватара")
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Цвет").font(PlanStyle.label)
                LazyVGrid(columns: colorColumns, alignment: .leading, spacing: 4) {
                    ForEach(customColors, id: \.self) { value in
                        let hex = String(format: "%06X", value)
                        swatch(.rgb(value), id: "custom-\(hex)", title: "#\(hex)")
                    }
                    swatch(.theme, id: "theme", title: "Цвет приложения")
                    ForEach(Self.palette) { option in
                        if let tint = option.tint {
                            swatch(tint, id: option.id, title: "\(option.title) · \(option.hex)")
                        }
                    }
                    customColorButton
                }
                .frame(maxWidth: 476, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Палитра аватара")
            }
        }
        .planCard(padding: 24)
        .onAppear {
            // Include an active custom color saved before the palette kept a history.
            if case .rgb(let value) = preferences.tint, !customColors.contains(value) {
                rememberCustomColor(value)
            }
        }
    }

    private var customColorButton: some View {
        Button { showsColorPicker.toggle() } label: {
            Circle()
                .fill(AngularGradient(colors: AvatarColorPopover.spectrum, center: .center))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(SetupOutlineButtonStyle(width: 44, height: 44, radius: 12, selected: showsColorPicker))
        .accessibilityLabel("Свой цвет")
        .accessibilityIdentifier("avatar-color-picker")
        .help("Свой цвет")
        .popover(isPresented: $showsColorPicker, arrowEdge: .bottom) {
            AvatarColorPopover(initialColor: preferences.tint.color.resolve(in: environment), shape: preferences.shape) { value in
                rememberCustomColor(value)
                preferences.tint = .rgb(value)
                showsColorPicker = false
            }
        }
    }

    private func rememberCustomColor(_ value: Int) {
        guard !Self.presetValues.contains(value) else { return }
        let colors = [value] + customColors.filter { $0 != value }
        savedCustomColors = colors.map(String.init).joined(separator: ",")
    }

    private func shapeButton(_ shape: AgentAvatarShape) -> some View {
        let selected = preferences.shape == shape
        return Button { preferences.shape = shape } label: {
            VStack(spacing: 2) {
                AgentAvatar.thumbnail(shape: shape, tint: preferences.tint, background: selected ? PlanStyle.soft : PlanStyle.card)
                    .frame(width: 52, height: 44)
                Text(shape.title)
                    .font(PlanStyle.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .foregroundStyle(selected ? PlanStyle.onSoft : PlanStyle.text)
        }
        .buttonStyle(SetupOutlineButtonStyle(height: 84, radius: 12, selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("avatar-shape-\(shape.rawValue)")
    }

    private func swatch(_ tint: AgentAvatarTint, id: String, title: String) -> some View {
        let selected = preferences.tint == tint
        let fill = tint.color
        return Button { preferences.tint = tint } label: {
            Circle()
                .fill(fill)
                .strokeBorder(PlanStyle.connector, lineWidth: 1)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(tint.markColor(on: fill.resolve(in: environment)))
                    }
                }
                .frame(width: 26, height: 26)
        }
        .buttonStyle(SetupOutlineButtonStyle(width: 44, height: 44, radius: 12, selected: selected))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("avatar-swatch-\(id)")
        .help(title)
    }
}
