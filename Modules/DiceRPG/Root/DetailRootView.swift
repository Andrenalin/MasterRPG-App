// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        CoreRPG.DetailRootView {
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
    
    var model: DiceConfigDataModel? {
        root.itemController.model(for: root.listControllable.listModel.selectedItemId)
    }
    
    func detailEditorView(model: DiceConfigDataModel) -> some View {
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
    @Previewable @Query var models: [DiceDataModel]
    @Previewable @Environment(DiceRootModel.self) var root
    
    DetailRootView().onAppear {
        root.listControllable.listModel.set(selectedItemId: models.first!.id)
    }
}
