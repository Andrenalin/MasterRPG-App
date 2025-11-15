// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DiceEditor: View {
    let model: DiceModel
    
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        Section {
            LabeledContent {
                DiceViewer(model: model, isEditor: true)
            } label: {
                Text("Dice", bundle: .module)
            }
            .labelsHidden()

            LabeledContent {
                GroupBoxTV {
                    DiceBag(model: model)
                } label: {
                    Image(systemName: "bag")
                }
                .foregroundStyle(.secondary)
            } label: {
                Text("Add", bundle: .module)
            }
            .labelsHidden()
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
        }
    }
    
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    
    DiceEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}
