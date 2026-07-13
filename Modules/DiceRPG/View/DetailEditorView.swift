// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    DetailEditorView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}

#Preview("Overlay", traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    DiceOverlayView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}

struct DetailEditorView: View {
    let model: DiceModel

    var body: some View {
        DiceEditor(model: model)
        DiceOptionEditor(model: model)
        CoupEditor(model: model)
        FumbleEditor(model: model)
        RerollEditor(model: model)
        SpecialOptionEditor(model: model)
    }
}

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
