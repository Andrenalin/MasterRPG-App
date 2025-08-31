// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        CoreRPG.DetailRootView(selectedId: selectedId, moveDetails: true) {
            if let model {
                DiceViewer(model: model, isEditor: false)
            }
        } editor: {
            if let model {
#if os(macOS)
                ScrollView {
                    detailEditorView(model: model)
                }
#else
                
                detailEditorView(model: model)
                    .padding(.horizontal, -20)
#endif
            }
        }
    }
    
    var model: DiceDataModel? {
        root.itemController.model(for: selectedId ?? root.listControllable.listModel.selectedItemId)
    }
    
    func detailEditorView(model: DiceDataModel) -> some View {
        Form {
            DiceEditor(model: model)
            DiceOptionEditor(model: model)
            CoupEditor(model: model)
            FumbleEditor(model: model)
            RerollEditor(model: model)
            SpecialOptionEditor(model: model)
        }
    }
}

#Preview(traits: .mockData) {
    DetailRootView(selectedId: MockData.previewId)
}
