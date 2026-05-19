// @copyright André Trettin

import Combine
import SwiftUI

public struct MeshAnimationView: View {
    public init() {}

    static let meshColors: [Color] = [.red, .purple, .cyan, .mint, .teal, .indigo, .blue, .green, .orange]
    static func randomColors() -> [Color] {
        (0...24).map { _ in meshColors.randomElement()! }
    }

    @State private var points: [SIMD2<Float>] = [
        .init(0.00, 0.00),.init(0.25, 0.00),.init(0.50, 0.00),.init(0.75, 0.00),.init(1.00, 0.00),
        .init(0.00, 0.25),.init(0.25, 0.25),.init(0.50, 0.25),.init(0.75, 0.25),.init(1.00, 0.25),
        .init(0.00, 0.50),.init(0.25, 0.50),.init(0.50, 0.50),.init(0.75, 0.50),.init(1.00, 0.50),
        .init(0.00, 0.75),.init(0.25, 0.75),.init(0.50, 0.75),.init(0.75, 0.75),.init(1.00, 0.75),
        .init(0.00, 1.00),.init(0.25, 1.00),.init(0.50, 1.00),.init(0.75, 1.00),.init(1.00, 1.00)
    ]

    @State private var colors: [Color] = MeshAnimationView.randomColors()
    @State private var timerSubscription: AnyCancellable?

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            MeshGradient(width: 5, height: 5, points: points, colors: colors)
                .task(id: context.date) {
                    guard timerSubscription != nil else { return }
                    withAnimation(.smooth(duration: 3, extraBounce: 0)) {
                        colors = MeshAnimationView.randomColors()
                    }
                }
        }
        .onAppear {
            timerSubscription = AnyCancellable({})
        }
        .onDisappear {
            timerSubscription = nil
        }
    }
}

#Preview {
    MeshAnimationView()
        .ignoresSafeArea()
}
