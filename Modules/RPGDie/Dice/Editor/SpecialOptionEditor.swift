//// @copyright André Trettin
//
//import AndrenalinKit
//import SwiftUI
//
//struct SpecialOptionEditor: View {
//    let model: DiceModel
//    
//    @Environment(DiceRootModel.self) private var root
//
//    var body: some View {
//        @Bindable var model = model
//        Section {
//            ToggleEditor(model: $model.reorderDice, title: "Reorder dice by value", bundle: .module, icon: "textformat.123")
//
//            ToggleEditor(model: $model.addDiceActivate, title: "Add dice", bundle: .module, icon: "dice")
//
//            if model.addDiceActivate {
//                addDiceEditorView
//            }
//        } header: {
//#if os(macOS)
//            Divider()
//                .padding(.top)
//#endif
//            Text("Special Options", bundle: .module)
//                .font(.headline)
//                .frame(maxWidth: .infinity, alignment: .center)
//        }
//    }
//}
//
//private extension SpecialOptionEditor {
//
//    @ViewBuilder
//    var addDiceEditorView: some View {
//        @Bindable var model = model
//        LabeledContent {
//            TextIntEditor(model: $model.addDiceEvery, title: "Add Dice each Value", icon: "plus", prompt: "value", bundle: .module, range: model.minValue...model.maxValue)
//        } label: {
//            Text("Add", bundle: .module)
//        }
//    }
//}
//
//#Preview(traits: .mockData) {
//    @Previewable @Query var models: [DiceDataModel]
//
//    SpecialOptionEditor(model: models.first!)
//}
