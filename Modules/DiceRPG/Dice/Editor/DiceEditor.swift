// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DiceEditor: View {
    let model: DiceConfigDataModel
    
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
                GroupBox {
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
//            Text("Dice Editor", bundle: .module)
//                .font(.headline)
//                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceConfigDataModel]
    
    DiceEditor(model: models.first!)

}
