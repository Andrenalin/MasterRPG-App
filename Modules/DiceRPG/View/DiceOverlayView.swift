// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceOverlayView: View {
    let model: DiceModel

    var body: some View {
        GlassEffectContainerView {
            DiceViewer(model: model, isEditor: false)
                .padding()
#if os(visionOS)
                // `glassEffect` does not exist on visionOS: the system glass instead, so the
                // scrolled list does not show through the dice.
                .glassBackgroundEffect(in: .rect(cornerRadius: 28, style: .continuous))
#else
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
