import SwiftUI
import simd

nonisolated enum AgentAvatarPhase: Equatable {
    case idle, thinking, correct, incorrect

    fileprivate var face: BlobFace {
        switch self {
        case .idle: .attentive
        case .thinking: .neutral
        case .correct: .happy
        case .incorrect: .worried
        }
    }

    var accessibilityValue: String {
        switch self {
        case .idle: "Готов"
        case .thinking: "Codex проверяет ответ"
        case .correct: "Верный ответ"
        case .incorrect: "Неверный ответ"
        }
    }
}

struct AgentAvatar: View {
    private static let circleDiameter = 56.0
    // Leave room for tall silhouettes at the top of a jump.
    private static let radiusFraction = 0.30
    private static let canvasSide = circleDiameter / (2 * radiusFraction)
    static let size = CGSize(width: canvasSide, height: canvasSide)

    let phase: AgentAvatarPhase
    let shape: AgentAvatarShape
    let tint: AgentAvatarTint
    let isComposing: Bool
    let activate: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion: AvatarMotion

    init(phase: AgentAvatarPhase, shape: AgentAvatarShape, tint: AgentAvatarTint,
         isComposing: Bool, activate: @escaping () -> Void) {
        self.phase = phase
        self.shape = shape
        self.tint = tint
        self.isComposing = isComposing
        self.activate = activate
        _motion = State(initialValue: AvatarMotion(phase: phase))
    }

    var body: some View {
        let animated = !reduceMotion && scenePhase == .active
        let deadline = motion.settlesAt
        let paused = !animated || (phase != .thinking && !motion.isJumping && deadline == nil)

        Button {
            motion.wink(at: .now)
            activate()
        } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: paused)) { timeline in
                let pose = motion.pose(at: timeline.date, animated: animated)
                AvatarArtwork(shape: shape, tint: tint, background: PlanStyle.canvas, pose: pose,
                              radiusFraction: Self.radiusFraction)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Аватар агента")
        .onHover { isHovering in
            motion.setHover(isHovering, at: .now)
        }
        .onChange(of: phase) { _, phase in
            motion.change(to: phase, at: .now, animated: animated)
        }
        .onChange(of: isComposing) { _, composing in
            if composing {
                motion.widenEyes(at: .now)
            } else {
                motion.finishWideEyes(at: .now)
            }
        }
        .task(id: deadline) {
            guard let deadline else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            } catch { return }
            guard !Task.isCancelled, motion.settlesAt == deadline else { return }
            motion.settle()
        }
    }

    static func thumbnail(shape: AgentAvatarShape, tint: AgentAvatarTint, background: Color) -> some View {
        AvatarArtwork(shape: shape, tint: tint, background: background, pose: BlobPose(face: .attentive), radiusFraction: 0.38)
    }
}

private nonisolated struct AvatarMotion {
    private static let transitionDuration = 0.2
    private static let nodDuration = 0.55
    private var phase: AgentAvatarPhase
    private var phaseStartedAt = Date.now
    private var outgoingPose: BlobPose?
    private var reaction: Reaction?
    private var hoverJump: HoverJump?

    init(phase: AgentAvatarPhase) {
        self.phase = phase
    }

    var isJumping: Bool { hoverJump != nil }

    var settlesAt: Date? {
        let transitionEnd = outgoingPose.map { _ in
            phaseStartedAt.addingTimeInterval(phase == .correct ? Self.nodDuration : Self.transitionDuration)
        }
        return [transitionEnd, reaction?.endsAt, hoverJump?.endsAt].compactMap { $0 }.max()
    }

    mutating func change(to phase: AgentAvatarPhase, at date: Date, animated: Bool) {
        outgoingPose = animated ? phasePose(at: date) : nil
        self.phase = phase
        phaseStartedAt = date
    }

    mutating func wink(at date: Date) {
        if let reaction, reaction.face == .wink, date < reaction.endsAt { return }
        reaction = Reaction(face: .wink, startedAt: date, endsAt: date.addingTimeInterval(0.8),
                            hops: hoverJump?.isActive(at: date) != true)
    }

    mutating func widenEyes(at date: Date) {
        reaction = Reaction(face: .wideEyes, startedAt: date, endsAt: date.addingTimeInterval(1.8), hops: false)
    }

    mutating func finishWideEyes(at date: Date) {
        guard let current = reaction, current.face == .wideEyes else { return }
        reaction?.endsAt = min(current.endsAt, date.addingTimeInterval(0.20))
    }

    mutating func setHover(_ isHovering: Bool, at date: Date) {
        if isHovering {
            if hoverJump?.isActive(at: date) == true {
                hoverJump?.endsAt = nil
            } else {
                hoverJump = HoverJump(startedAt: date)
            }
        } else {
            hoverJump?.finishCycle(at: date)
        }
    }

    mutating func settle() {
        outgoingPose = nil
        reaction = nil
        if hoverJump?.endsAt != nil { hoverJump = nil }
    }

    func pose(at date: Date, animated: Bool) -> BlobPose {
        guard animated else { return BlobPose(face: reaction?.face.pose ?? phase.face) }

        var pose = phasePose(at: date)
        if let reaction {
            let amount = smoothStep(min(date.timeIntervalSince(reaction.startedAt) / 0.12,
                                        reaction.endsAt.timeIntervalSince(date) / 0.20))
            pose.face = pose.face.blended(toward: reaction.face.pose, amount: amount)
            pose.turn *= 1 - amount
        }

        if let progress = hoverJump?.progress(at: date) {
            pose.hop(progress: progress, height: 0.33, pitch: -0.25)
        } else if let reaction, reaction.hops {
            let duration = reaction.endsAt.timeIntervalSince(reaction.startedAt)
            pose.hop(progress: date.timeIntervalSince(reaction.startedAt) / duration, height: 0.25)
        }
        return pose
    }

    private struct Reaction {
        enum Face {
            case wink, wideEyes

            var pose: BlobFace {
                switch self {
                case .wink: .wink
                case .wideEyes: .wideEyes
                }
            }
        }

        let face: Face
        let startedAt: Date
        var endsAt: Date
        let hops: Bool
    }

    private func phasePose(at date: Date) -> BlobPose {
        let elapsed = max(0, date.timeIntervalSince(phaseStartedAt))
        var pose = BlobPose(face: phase.face)
        switch phase {
        case .thinking:
            let cycle = 2 * Double.pi * elapsed / 2.6
            pose.turn = SIMD2(0.11 * sin(cycle), 0.05 * sin(cycle + .pi / 2))
            pose.scale.y += 0.025 * sin(cycle)
        case .correct:
            let nod = halfWave((elapsed - 0.13) / 0.40)
            if outgoingPose != nil {
                pose.turn.y = 0.32 * nod
                pose.scale.y -= 0.055 * nod
                pose.y += 0.055 * nod
            }
        case .incorrect:
            pose.tilt = -0.08
        case .idle:
            break
        }
        if let outgoingPose {
            pose = outgoingPose.blended(toward: pose, amount: smoothStep(elapsed / Self.transitionDuration))
        }
        return pose
    }
}

private nonisolated struct HoverJump {
    private static let duration = 1.6
    let startedAt: Date
    var endsAt: Date?

    func isActive(at date: Date) -> Bool {
        endsAt.map { date < $0 } ?? true
    }

    mutating func finishCycle(at date: Date) {
        guard endsAt == nil else { return }
        let cycle = max(1, floor(date.timeIntervalSince(startedAt) / Self.duration))
        let boundary = startedAt.addingTimeInterval(cycle * Self.duration)
        endsAt = date <= boundary ? boundary : startedAt.addingTimeInterval((cycle + 1) * Self.duration)
    }

    func progress(at date: Date) -> Double? {
        guard isActive(at: date) else { return nil }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        let hopDuration = Self.duration / 2
        return elapsed.truncatingRemainder(dividingBy: hopDuration) / hopDuration
    }
}

private struct AvatarArtwork: View {
    let shape: AgentAvatarShape
    let tint: AgentAvatarTint
    let background: Color
    let pose: BlobPose
    let radiusFraction: Double
    @Environment(\.self) private var environment

    var body: some View {
        let geometry = shape.geometry
        let fill = tint.color
        let resolved = fill.resolve(in: environment)
        let eyes = tint.markColor(on: resolved)
        let backdrop = background.resolve(in: environment).avatarLuminance
        let bodyLuminance = resolved.avatarLuminance
        // Keep a custom fill visible when it is close to the surrounding surface.
        let contrast = (max(bodyLuminance, backdrop) + 0.05) / (min(bodyLuminance, backdrop) + 0.05)
        let border = contrast < 3 ? PlanStyle.connector : nil

        Canvas { context, size in
            let radius = min(size.width, size.height) * radiusFraction
            BlobAvatar.draw(pose, geometry: geometry, in: context, size: size, radius: radius,
                            fill: fill, eyes: eyes, border: border)
        }
        .accessibilityHidden(true)
    }
}

// Eye poses, spherical projection and hop motion are adapted from blob-avatar.
// https://github.com/c0le0ni/blob-avatar — see BlobAvatar-LICENSE.txt.
private nonisolated enum BlobAvatar {
    static func draw(_ pose: BlobPose, geometry: AvatarGeometry, in context: GraphicsContext,
                     size: CGSize, radius: Double, fill: Color, eyes: Color, border: Color?) {
        var context = context
        guard radius > 0 else { return }
        let y = pose.y + geometry.bottom * pose.groundOffset
        context.translateBy(x: size.width / 2, y: size.height / 2 + radius * y)
        context.rotate(by: .radians(pose.tilt))
        context.scaleBy(x: radius * pose.scale.x, y: radius * pose.scale.y)
        context.fill(geometry.outline, with: .color(fill))
        if let border { context.stroke(geometry.outline, with: .color(border), lineWidth: 1 / radius) }

        let (left, right) = pose.face.projected(turn: pose.turn, in: geometry)
        context.fill(left.path, with: .color(eyes))
        context.fill(right.path, with: .color(eyes))
    }
}

private nonisolated struct BlobPose {
    var face: BlobFace
    var turn = SIMD2<Double>.zero
    var scale = SIMD2<Double>(repeating: 1)
    var y = 0.0
    var groundOffset = 0.0
    var tilt = 0.0

    mutating func hop(progress: Double, height: Double, pitch: Double = 0) {
        let air = unitInterval((progress - 0.2) / 0.45)
        let arc = halfWave(air)
        let squash = 0.08 * arc - 0.16 * halfWave(progress / 0.22)
            - 0.09 * halfWave((progress - 0.65) / 0.35)
        y += 4 * height * air * (air - 1)
        groundOffset -= scale.y * squash
        scale *= SIMD2(1 - 0.7 * squash, 1 + squash)
        turn.y += pitch * arc
    }

    func blended(toward target: Self, amount: Double) -> Self {
        Self(face: face.blended(toward: target.face, amount: amount),
             turn: turn + (target.turn - turn) * amount,
             scale: scale + (target.scale - scale) * amount,
             y: y + (target.y - y) * amount,
             groundOffset: groundOffset + (target.groundOffset - groundOffset) * amount,
             tilt: tilt + (target.tilt - tilt) * amount)
    }
}

private nonisolated struct BlobFace {
    let left: BlobEye
    let right: BlobEye

    static let attentive = Self(left: BlobEye(-0.212, -0.065, 0.21, 0.44, SIMD4(0.973, -0.095, 0.08, 0.991)),
                                right: BlobEye(0.336, -0.106, 0.21, 0.44, SIMD4(0.937, -0.046, 0.08, 0.991)))
    static let neutral = Self(left: BlobEye(0.188, -0.406, 0.186, 0.412, SIMD4(0.889, -0.314, 0.414, 0.857)),
                              right: BlobEye(0.618, -0.51, 0.186, 0.412, SIMD4(0.667, -0.061, 0.414, 0.857)))
    static let happy = Self(left: BlobEye(-0.203, -0.155, 0.27, 0.17, SIMD4(0.952, 0.198, -0.227, 0.967)),
                            right: BlobEye(0.378, -0.152, 0.27, 0.17, SIMD4(0.894, -0.188, 0.233, 0.969)))
    static let worried = Self(left: BlobEye(-0.352, -0.112, 0.24, 0.44, SIMD4(0.9, -0.314, 0.258, 0.943)),
                              right: BlobEye(0.315, -0.142, 0.24, 0.44, SIMD4(0.912, 0.318, -0.262, 0.938)))
    static let wink = Self(left: BlobEye(-0.345, -0.115, 0.24, 0.46, SIMD4(0.94, 0.06, -0.1, 0.99)),
                           right: BlobEye(0.205, -0.065, 0.45, 0.09, SIMD4(0.97, 0.12, -0.1, 0.99)))
    static let wideEyes = Self(left: BlobEye(-0.175, 0.28, 0.36, 0.88, SIMD4(0.96, 0.26, -0.22, 0.93)),
                               right: BlobEye(0.435, 0.385, 0.36, 0.88, SIMD4(0.87, 0.05, -0.22, 0.93)))

    func blended(toward target: Self, amount: Double) -> Self {
        Self(left: left.blended(toward: target.left, amount: amount),
             right: right.blended(toward: target.right, amount: amount))
    }

    func projected(turn: SIMD2<Double>, in geometry: AvatarGeometry) -> (ProjectedAvatarEye, ProjectedAvatarEye) {
        var first = left.projected(turn: turn, in: geometry)
        var second = right.projected(turn: turn, in: geometry)
        let separation = second.center - first.center
        let distance = simd_length(separation)
        if distance > 0 {
            let normal = separation / distance
            let span = first.extent(along: normal) + second.extent(along: normal)
            let scale = min(1, max(0.6, (distance - 0.03) / span))
            first.size *= scale
            second.size *= scale
        }
        return (first, second)
    }
}

private nonisolated struct BlobEye {
    let center: SIMD2<Double>
    let size: SIMD2<Double>
    // The two columns of the capsule's projection onto the screen.
    let axes: SIMD4<Double>

    init(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ axes: SIMD4<Double>) {
        center = SIMD2(x, y)
        size = SIMD2(width, height)
        self.axes = axes
    }

    func blended(toward target: Self, amount: Double) -> Self {
        let center = center + (target.center - center) * amount
        let size = size + (target.size - size) * amount
        return Self(center.x, center.y, size.x, size.y, axes + (target.axes - axes) * amount)
    }

    func projected(turn: SIMD2<Double>, in geometry: AvatarGeometry) -> ProjectedAvatarEye {
        let depth = sqrt(max(0.0225, 1 - simd_dot(center, center)))
        let yawCos = cos(turn.x), yawSin = sin(turn.x)
        let pitchCos = cos(turn.y), pitchSin = sin(turn.y)

        func projected(_ point: SIMD2<Double>, depth: Double) -> SIMD2<Double> {
            let turnedDepth = depth * yawCos - point.x * yawSin
            return SIMD2(point.x * yawCos + depth * yawSin, point.y * pitchCos + turnedDepth * pitchSin)
        }
        func tangent(_ axis: SIMD2<Double>) -> SIMD2<Double> {
            projected(axis, depth: -simd_dot(axis, center) / depth)
        }

        let position = projected(center, depth: depth)
        let horizontal = tangent(SIMD2(axes.x, axes.y))
        let vertical = tangent(SIMD2(axes.z, axes.w))
        var eye = ProjectedAvatarEye(center: position * geometry.faceRadius(toward: position),
                                     size: size * geometry.faceScale, horizontal: horizontal, vertical: vertical)
        eye.fit(in: geometry)
        return eye
    }
}

private nonisolated struct ProjectedAvatarEye {
    var center: SIMD2<Double>
    var size: SIMD2<Double>
    let horizontal: SIMD2<Double>
    let vertical: SIMD2<Double>

    private static let directions = (0..<20).map { index in
        let angle = Double(index) * .pi / 10
        return SIMD2(cos(angle), sin(angle))
    }

    private var radius: Double { min(size.x, size.y) / 2 }
    private var spine: SIMD2<Double> { size / 2 - SIMD2(repeating: radius) }

    mutating func fit(in geometry: AvatarGeometry) {
        // Keep the eyes inside the silhouette, or below the ears on animal shapes.
        let radius = radius, spine = spine
        for _ in 0..<4 {
            let overrun = Self.directions.reduce(1.0) { worst, direction in
                let spineEnd = SIMD2(direction.x < 0 ? -spine.x : spine.x, direction.y < 0 ? -spine.y : spine.y)
                let local = direction * radius + spineEnd
                let point = center + horizontal * local.x + vertical * local.y
                return max(worst, simd_length(point) / (0.9 * geometry.faceRadius(toward: point)))
            }
            if overrun <= 1 { break }
            center *= max(0.5, 1 - 1.1 * (overrun - 1))
        }
    }

    func extent(along normal: SIMD2<Double>) -> Double {
        let x = simd_dot(horizontal, normal), y = simd_dot(vertical, normal)
        return radius * hypot(x, y) + abs(x) * spine.x + abs(y) * spine.y
    }

    var path: Path {
        let rect = CGRect(x: -size.x / 2, y: -size.y / 2, width: size.x, height: size.y)
        let capsule = Path(roundedRect: rect, cornerRadius: radius, style: .circular)
        return capsule.applying(CGAffineTransform(a: horizontal.x, b: horizontal.y, c: vertical.x, d: vertical.y,
                                                  tx: center.x, ty: center.y))
    }
}

private nonisolated func unitInterval(_ value: Double) -> Double { min(1, max(0, value)) }

private nonisolated func smoothStep(_ value: Double) -> Double {
    let x = unitInterval(value)
    return x * x * (3 - 2 * x)
}

private nonisolated func halfWave(_ value: Double) -> Double { sin(.pi * unitInterval(value)) }
