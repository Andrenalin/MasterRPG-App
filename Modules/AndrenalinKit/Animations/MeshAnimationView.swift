// @copyright André Trettin

import SwiftUI

public struct MeshAnimationView: View {
    public init() {}
    
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
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
    
    public var body: some View {
        MeshGradient(width: 5, height: 5, points: points, colors: colors)
            .onReceive(timer) { _ in
                withAnimation(.easeInOut(duration: 5)) {
                    colors = MeshAnimationView.randomColors()
                }
            }
    }
}

#Preview {
    MeshAnimationView()
        .ignoresSafeArea()
}
