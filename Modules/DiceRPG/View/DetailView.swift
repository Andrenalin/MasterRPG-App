// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailView: View {
    let model: DiceDataModel

    @Environment(DiceRootModel.self) private var root
    @Environment(ListModel.self) private var listModel

    @State private var selection = GroupItemSelectionModel()
    @State private var openFileWindowModel = OpenFileWindowModel()

    var body: some View {
        FileDetailEditorView(model: model, editController: root.editController, menuController: menuController, fileTypes: []) {
            DiceRoute.detail($0)
        } importer: {
        } background: {
            backgroundHeader
        } editor: {
            if !model.specialCategory {
#if os(macOS)
                ScrollView {
                    detailEditorView
                }
#else
                detailEditorView
                    .padding(.horizontal, -20)
#endif
            }
        } row: {
            MainRowView(model: $0)
        } bottom: {
            ItemGroupItemView(model: model)
        }
        .environment(selection)
        .environment(openFileWindowModel)
    }
}

private extension DetailView {
    var backgroundHeader: some View {
        DiceViewer(model: model, isEditor: false)
            .background {
                ConcentricRectangle().fill(DiceDataModel.typeId.color.gradient)
                    .ignoresSafeArea(edges: .top)
                    .backgroundExtensionEffect()
            }
    }
    
    var detailEditorView: some View {
        Form {
            DiceEditor(model: model)
            DiceOptionEditor(model: model)
            CoupEditor(model: model)
            FumbleEditor(model: model)
            RerollEditor(model: model)
            SpecialOptionEditor(model: model)
        }
    }

    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]
    
    DetailView(model: models[0])
}
