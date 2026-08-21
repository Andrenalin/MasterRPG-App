// @copyright André Trettin

import SwiftUI

public struct MeshAnimationView: View {
    public init(animates: Bool = true) {
        self.animates = animates
        self._colors = State(initialValue: animates ? Self.randomColors() : Self.staticColors)
    }

    private static let meshColors: [Color] = [.red, .purple, .cyan, .mint, .teal, .indigo, .blue, .green, .orange]
    private static let staticColors: [Color] = [
        .red, .purple, .cyan, .mint, .teal,
        .indigo, .blue, .green, .orange, .red,
        .purple, .cyan, .mint, .teal, .indigo,
        .blue, .green, .orange, .red, .purple,
        .cyan, .mint, .teal, .indigo, .blue
    ]
    private static let points: [SIMD2<Float>] = [
        .init(0.00, 0.00), .init(0.25, 0.00), .init(0.50, 0.00), .init(0.75, 0.00), .init(1.00, 0.00),
        .init(0.00, 0.25), .init(0.25, 0.25), .init(0.50, 0.25), .init(0.75, 0.25), .init(1.00, 0.25),
        .init(0.00, 0.50), .init(0.25, 0.50), .init(0.50, 0.50), .init(0.75, 0.50), .init(1.00, 0.50),
        .init(0.00, 0.75), .init(0.25, 0.75), .init(0.50, 0.75), .init(0.75, 0.75), .init(1.00, 0.75),
        .init(0.00, 1.00), .init(0.25, 1.00), .init(0.50, 1.00), .init(0.75, 1.00), .init(1.00, 1.00)
    ]

    /// Cadence between re-randomizing the mesh's colors. See CODE_AUDIT §9.14.
    private static let colorCycleInterval: Duration = .seconds(15)

    private static func randomColors() -> [Color] {
        (0..<25).map { _ in meshColors.randomElement() ?? .blue }
    }

    private let animates: Bool
    @Environment(\.meshAnimationEnabled) private var meshAnimationEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var colors: [Color]

    public var body: some View {
        let shouldAnimate = animates && meshAnimationEnabled && !accessibilityReduceMotion

        MeshGradient(
            width: 5,
            height: 5,
            points: Self.points,
            colors: shouldAnimate ? colors : Self.staticColors
        )
            .task(id: shouldAnimate) {
                guard shouldAnimate else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.colorCycleInterval)
                    guard !Task.isCancelled else { break }
                    withAnimation(.smooth(duration: 3)) {
                        colors = Self.randomColors()
                    }
                }
            }
    }
}

#Preview {
    MeshAnimationView(animates: false)
        .ignoresSafeArea()
}

private struct MeshAnimationEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    var meshAnimationEnabled: Bool {
        get { self[MeshAnimationEnabledKey.self] }
        set { self[MeshAnimationEnabledKey.self] = newValue }
    }
}

public extension View {
    func meshAnimationEnabled(_ isEnabled: Bool) -> some View {
        environment(\.meshAnimationEnabled, isEnabled)
    }
}
