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

    var body: some View {
        WeatherViewerContainer(model: model, useGame: false, isAnimating: $animate) { viewer in
            viewer
#if !os(visionOS)
                .glassEffect(.clear)
#endif
                .clipShape(.capsule)
        }
        .padding(.horizontal, 16)
        .frame(height: 128)
    }
}
