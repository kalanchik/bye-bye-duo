import AppKit
import SwiftUI

struct AvatarColorPopover: View {
    let shape: AgentAvatarShape
    let add: (Int) -> Void

    @Environment(\.self) private var environment
    @State private var color: Components
    @State private var hex: String

    static let spectrum = (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }

    init(initialColor: Color.Resolved, shape: AgentAvatarShape, add: @escaping (Int) -> Void) {
        self.shape = shape
        self.add = add
        _color = State(initialValue: Components(initialColor))
        _hex = State(initialValue: Self.hexadecimal(AgentAvatarTint(resolved: initialColor).rawValue))
    }

    var body: some View {
        VStack(spacing: 12) {
            colorField
            hueTrack
            HStack(spacing: 10) {
                let tint = AgentAvatarTint(resolved: color.fill.resolve(in: environment))
                AgentAvatar.thumbnail(shape: shape, tint: tint, background: PlanStyle.card)
                    .frame(width: 36, height: 36)
                TextField("HEX", text: hexBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 99)
                    .accessibilityLabel("HEX цвета")
                    .accessibilityIdentifier("avatar-custom-hex")
                    .onSubmit(addColor)
                Spacer(minLength: 0)
                Button(action: addColor) {
                    Text("Добавить").foregroundStyle(PlanStyle.onAction)
                }
                .buttonStyle(.borderedProminent)
                .tint(PlanStyle.action)
                .disabled(Self.parseHex(hex) == nil)
            }
        }
        .frame(width: 256)
        .padding(16)
    }

    private var colorField: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color(hue: color.hue, saturation: 1, brightness: 1)
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                marker(color.fill)
                    .position(x: clampMarker(size.width * color.saturation, limit: size.width),
                              y: clampMarker(size.height * (1 - color.brightness), limit: size.height))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                updateColor {
                    $0.saturation = unit(drag.location.x / size.width)
                    $0.brightness = 1 - unit(drag.location.y / size.height)
                }
            })
        }
        .frame(height: 132)
        .accessibilityRepresentation {
            VStack {
                Slider(value: component(\.saturation), in: 0...1) { Text("Насыщенность") }
                Slider(value: component(\.brightness), in: 0...1) { Text("Яркость") }
            }
        }
    }

    private var hueTrack: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Capsule()
                .fill(LinearGradient(colors: Self.spectrum, startPoint: .leading, endPoint: .trailing))
                .frame(height: 10)
                .frame(maxHeight: .infinity)
                .overlay {
                    marker(Color(hue: color.hue, saturation: 1, brightness: 1))
                        .position(x: clampMarker(size.width * color.hue, limit: size.width), y: size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    updateColor { $0.hue = unit(drag.location.x / size.width) }
                })
        }
        .frame(height: 22)
        .accessibilityRepresentation { Slider(value: component(\.hue), in: 0...1) { Text("Тон") } }
    }

    private func marker(_ fill: Color) -> some View {
        Circle().fill(fill)
            .strokeBorder(.white, lineWidth: 2)
            .strokeBorder(.black.opacity(0.65), lineWidth: 1)
            .frame(width: 16, height: 16)
            .allowsHitTesting(false)
    }

    private func clampMarker(_ value: CGFloat, limit: CGFloat) -> CGFloat { min(limit - 8, max(8, value)) }

    private func unit(_ value: Double) -> Double { min(1, max(0, value)) }

    private func component(_ key: WritableKeyPath<Components, Double>) -> Binding<Double> {
        Binding(get: { color[keyPath: key] }, set: { value in updateColor { $0[keyPath: key] = value } })
    }

    private func updateColor(_ update: (inout Components) -> Void) {
        update(&color)
        hex = Self.hexadecimal(AgentAvatarTint(resolved: color.fill.resolve(in: environment)).rawValue)
    }

    private var hexBinding: Binding<String> {
        Binding(get: { hex }, set: { input in
            hex = input
            if let value = Self.parseHex(input) {
                color = Components(AgentAvatarTint.rgb(value).color.resolve(in: environment), fallbackHue: color.hue)
            }
        })
    }

    private func addColor() {
        if let value = Self.parseHex(hex) { add(value) }
    }

    private static func hexadecimal(_ value: Int) -> String { String(format: "#%06X", value) }

    private static func parseHex(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.first == "#" ? trimmed.dropFirst() : trimmed[...]
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return Int(digits, radix: 16)
    }

    private struct Components {
        var hue: Double
        var saturation: Double
        var brightness: Double

        init(_ color: Color.Resolved, fallbackHue: Double = 0) {
            let native = NSColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green),
                                 blue: CGFloat(color.blue), alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
            native.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
            self.hue = saturation > 0 ? hue : fallbackHue
            self.saturation = saturation
            self.brightness = brightness
        }

        var fill: Color { Color(hue: hue, saturation: saturation, brightness: brightness) }
    }
}
