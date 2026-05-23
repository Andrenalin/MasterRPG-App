// @copyright André Trettin

import SwiftUI

public struct MeshAnimationView: View {
    public init() {}

    private static let meshColors: [Color] = [.red, .purple, .cyan, .mint, .teal, .indigo, .blue, .green, .orange]
    private static let points: [SIMD2<Float>] = [
        .init(0.00, 0.00), .init(0.25, 0.00), .init(0.50, 0.00), .init(0.75, 0.00), .init(1.00, 0.00),
        .init(0.00, 0.25), .init(0.25, 0.25), .init(0.50, 0.25), .init(0.75, 0.25), .init(1.00, 0.25),
        .init(0.00, 0.50), .init(0.25, 0.50), .init(0.50, 0.50), .init(0.75, 0.50), .init(1.00, 0.50),
        .init(0.00, 0.75), .init(0.25, 0.75), .init(0.50, 0.75), .init(0.75, 0.75), .init(1.00, 0.75),
        .init(0.00, 1.00), .init(0.25, 1.00), .init(0.50, 1.00), .init(0.75, 1.00), .init(1.00, 1.00)
    ]

    private static func randomColors() -> [Color] {
        (0..<25).map { _ in meshColors.randomElement() ?? .blue }
    }

    @State private var colors: [Color] = MeshAnimationView.randomColors()

    public var body: some View {
        MeshGradient(width: 5, height: 5, points: Self.points, colors: colors)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { break }
                    withAnimation(.smooth(duration: 3)) {
                        colors = Self.randomColors()
                    }
                }
            }
    }
}

#Preview {
    MeshAnimationView()
        .ignoresSafeArea()
}
