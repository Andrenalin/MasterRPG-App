// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(WeatherRootModel.self) var root
    @Previewable @State var animate = true
    OverlayViewer(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), animate: $animate)
}

struct OverlayViewer: View {
    let model: WeatherModel
    @Binding var animate: Bool
    
    @Environment(WeatherRootModel.self) private var root

    @State private var containerSize: CGSize = .zero

    var body: some View {
        Color.clear
            .overlay {
                WeatherViewer(model: model, size: containerSize, useGame: false, isAnimating: $animate)
#if !os(visionOS)
                    .glassEffect(.clear)
#endif
                    .clipShape(.capsule)
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newValue in
                containerSize = newValue
            }
            .padding(.horizontal, 16)
            .frame(height: 128)
    }
}
