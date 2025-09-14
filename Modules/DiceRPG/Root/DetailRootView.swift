// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(DiceRootModel.self) private var root
        
    @State private var openFileWindowModel = OpenFileWindowModel()
    
    var body: some View {
        ItemDetailRootView(selectedId: selectedId) {
        } editor: {
            if let model {
                DiceViewer(model: model, isEditor: false)

                detailEditorView(model: model)
            }
        } overlay: {
            diceOverlay
        }
        .environment(openFileWindowModel)
    }
    
    var model: DiceDataModel? {
        root.itemController.model(for: selectedId ?? root.listControllable.listModel.selectedItemId)
    }

    @ViewBuilder
    func detailEditorView(model: DiceDataModel) -> some View {
            DiceEditor(model: model)
            DiceOptionEditor(model: model)
            CoupEditor(model: model)
            FumbleEditor(model: model)
            RerollEditor(model: model)
            SpecialOptionEditor(model: model)
    }
    
    @ViewBuilder
    var diceOverlay: some View {
        if let model {
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
}

#Preview(traits: .mockData) {
    DetailRootView(selectedId: MockData.previewId)
}
