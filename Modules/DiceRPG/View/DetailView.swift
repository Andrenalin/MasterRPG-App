//// @copyright André Trettin
//
//import CoreRPG
//import SwiftData
//import SwiftUI
//
//struct DetailView: View {
//    let model: DiceDataModel
//
//    @Environment(DiceRootModel.self) private var root
//
//    @State private var selection = GroupItemSelectionModel()
//    @State private var openFileWindowModel = OpenFileWindowModel()
//
//    var body: some View {
//        FileDetailEditorView(model: model, listController: root.listController, editController: root.editController, menuController: menuController, fileTypes: []) {
//            DiceRoute.detail($0)
//        } importer: {
//        } background: {
//            backgroundHeader
//        } editor: {
//            if !model.specialCategory {
//#if os(macOS)
//                ScrollView {
//                    detailEditorView
//                }
//#else
//                detailEditorView
//                    .padding(.horizontal, -20)
//#endif
//            }
//        } row: { itemId in
//            if let model = root.itemController.modelSync(for: itemId) {
//                MainRowView(model: model)
//            }
//        } bottom: {
//            OldItemGroupItemView(model: model)
//        } inspector: {
//            LinkRootView(isInspector: true)
//        }
//        .environment(selection)
//        .environment(openFileWindowModel)
//    }
//}
//
//private extension DetailView {
//    var backgroundHeader: some View {
//        DiceViewer(model: model, isEditor: false)
//            .background {
//                ConcentricRectangle().fill(DiceDataModel.typeId.color.gradient)
//                    .ignoresSafeArea(edges: .top)
//                    .backgroundExtensionEffect()
//            }
//    }
//    
//    var detailEditorView: some View {
//        Form {
//            DiceEditor(model: model)
//            DiceOptionEditor(model: model)
//            CoupEditor(model: model)
//            FumbleEditor(model: model)
//            RerollEditor(model: model)
//            SpecialOptionEditor(model: model)
//        }
//    }
//
//    var menuController: any ItemListContextMenuControllable {
//        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: root.listController.listModel)
//    }
//}
//
//#Preview(traits: .mockData) {
//    @Previewable @Query var models: [DiceDataModel]
//    
//    DetailView(model: models[0])
//}
