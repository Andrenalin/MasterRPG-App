// @copyright André Trettin

import CoreRPG
import SwiftUI

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
