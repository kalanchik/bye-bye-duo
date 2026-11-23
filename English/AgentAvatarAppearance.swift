import SwiftUI

nonisolated enum AgentAvatarShape: String, CaseIterable, Identifiable {
    case circle, pebble, squircle, capsule, triangle, diamond, hexagon, star, cloud, droplet, heart
    case ghost, cat, bear, bunny, amoeba, flower, clover, leaf, gem, bubble

    var id: Self { self }

    var title: String {
        switch self {
        case .circle: "Круг"
        case .pebble: "Камешек"
        case .squircle: "Мягкий квадрат"
        case .capsule: "Капсула"
        case .triangle: "Треугольник"
        case .diamond: "Ромб"
        case .hexagon: "Гексагон"
        case .star: "Звезда"
        case .cloud: "Облако"
        case .droplet: "Капля"
        case .heart: "Сердце"
        case .ghost: "Призрак"
        case .cat: "Кот"
        case .bear: "Медведь"
        case .bunny: "Кролик"
        case .amoeba: "Амёба"
        case .flower: "Цветок"
        case .clover: "Клевер"
        case .leaf: "Лист"
        case .gem: "Кристалл"
        case .bubble: "Облачко речи"
        }
    }

    var geometry: AvatarGeometry { AvatarGeometry.forShape(self) }
}

struct AgentAvatarPreferences: DynamicProperty {
    @AppStorage("agentAvatarShape") var shape: AgentAvatarShape = .pebble
    @AppStorage("agentAvatarColor") var tint: AgentAvatarTint = .theme
}

// A custom color is stored as opaque 24-bit sRGB.
nonisolated enum AgentAvatarTint: RawRepresentable, Equatable {
    case theme
    case rgb(Int)

    init?(rawValue: Int) {
        if rawValue == -1 { self = .theme }
        else if (0...0xFFFFFF).contains(rawValue) { self = .rgb(rawValue) }
        else { return nil }
    }

    var rawValue: Int {
        switch self {
        case .theme: -1
        case .rgb(let rgb): rgb
        }
    }

    init(resolved color: Color.Resolved) {
        func channel(_ value: Float) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        self = .rgb((channel(color.red) << 16) | (channel(color.green) << 8) | channel(color.blue))
    }

    @MainActor
    var color: Color {
        guard case .rgb(let rgb) = self else { return PlanStyle.action }
        return Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }

    @MainActor
    func markColor(on resolved: Color.Resolved) -> Color {
        if self == .theme { return PlanStyle.onAction }
        return resolved.avatarLuminance >= 0.179 ? .black : .white
    }
}

extension Color.Resolved {
    nonisolated var avatarLuminance: Float {
        0.2126 * linearRed + 0.7152 * linearGreen + 0.0722 * linearBlue
    }
}

nonisolated struct BlobAvatarCatalog: Decodable {
    fileprivate struct Shape: Decodable {
        let outline: [[Double]]
        let faceScale: Double
        let faceRadii: [Double]
    }

    struct Swatch: Decodable, Identifiable {
        let id: String
        let hex: String

        var tint: AgentAvatarTint? {
            guard let rgb = Int(hex.dropFirst(), radix: 16) else { return nil }
            return AgentAvatarTint(rawValue: rgb)
        }

        var title: String {
            switch id {
            case "ink": "Чёрный"
            case "brown": "Коричневый"
            case "red": "Красный"
            case "orange": "Оранжевый"
            case "amber": "Янтарный"
            case "lime": "Лаймовый"
            case "turquoise": "Бирюзовый"
            case "blue": "Синий"
            case "purple": "Фиолетовый"
            case "pink": "Розовый"
            case "grey": "Серый"
            case "cream": "Кремовый"
            case "coral": "Коралловый"
            case "sand": "Песочный"
            case "forest": "Лесной зелёный"
            case "mint": "Мятный"
            case "sky": "Голубой"
            case "lavender": "Лавандовый"
            default: hex
            }
        }
    }

    fileprivate let shapes: [String: Shape]
    let palette: [Swatch]

    static let bundled: Self = {
        guard let url = Bundle.main.url(forResource: "BlobAvatarCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(shapes: [:], palette: [])
        }
        return catalog
    }()
}

// BlobAvatarCatalog.json contains the upstream contours and face radii in body units.
// The origin and revision are recorded in the resource. See BlobAvatar-LICENSE.txt.
nonisolated struct AvatarGeometry {
    let outline: Path
    let bottom: Double
    let faceScale: Double
    private let faceRadii: [Double]

    private static let shapes = BlobAvatarCatalog.bundled.shapes.compactMapValues(Self.init)
    private static let circle = Self(outline: Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                                     faceScale: 1, faceRadii: [])

    static func forShape(_ shape: AgentAvatarShape) -> Self { shapes[shape.rawValue] ?? circle }

    private init(outline: Path, faceScale: Double, faceRadii: [Double]) {
        self.outline = outline
        bottom = outline.boundingRect.maxY
        self.faceScale = faceScale
        self.faceRadii = faceRadii
    }

    private init?(record: BlobAvatarCatalog.Shape) {
        guard record.outline.count == 56, record.outline.allSatisfy({ $0.count == 2 }),
              record.faceRadii.count == 128, record.faceRadii.allSatisfy({ $0 > 0 }), record.faceScale > 0 else { return nil }
        let points = record.outline.map { SIMD2($0[0], $0[1]) }
        func point(at index: Int) -> SIMD2<Double> { points[(index + points.count) % points.count] }
        func cgPoint(_ point: SIMD2<Double>) -> CGPoint { CGPoint(x: point.x, y: point.y) }

        var path = Path()
        path.move(to: cgPoint(points[0]))
        for index in points.indices {
            let start = point(at: index)
            let end = point(at: index + 1)
            // Catmull–Rom tangents preserve smooth joins on the sampled silhouette.
            let first = start + (end - point(at: index - 1)) / 6
            let second = end - (point(at: index + 2) - start) / 6
            path.addCurve(to: cgPoint(end), control1: cgPoint(first), control2: cgPoint(second))
        }
        path.closeSubpath()
        self.init(outline: path, faceScale: record.faceScale, faceRadii: record.faceRadii)
    }

    func faceRadius(toward point: SIMD2<Double>) -> Double {
        guard !faceRadii.isEmpty else { return 1 }
        let angle = atan2(point.x, -point.y)
        let turn = 2 * Double.pi
        let sample = (angle < 0 ? angle + turn : angle) * Double(faceRadii.count) / turn
        let index = Int(sample)
        let first = faceRadii[index % faceRadii.count]
        let next = faceRadii[(index + 1) % faceRadii.count]
        return first + (next - first) * (sample - Double(index))
    }
}
