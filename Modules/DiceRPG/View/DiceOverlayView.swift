// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceOverlayView: View {
    let model: DiceModel

    var body: some View {
        GlassEffectContainerView {
            DiceViewer(model: model, isEditor: false)
                .padding()
#if !os(visionOS)
                .glassEffect(.clear)
#endif
        }
        .padding()
    }
}

#Preview("Overlay", traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    DiceOverlayView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}
