// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        CoreRPG.DetailRootView(selectedId: selectedId) {
        } editor: {
            if let model {
                DiceViewer(model: model, isEditor: false)

                detailEditorView(model: model)
            }
        }
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
}

#Preview(traits: .mockData) {
    DetailRootView(selectedId: MockData.previewId)
}
