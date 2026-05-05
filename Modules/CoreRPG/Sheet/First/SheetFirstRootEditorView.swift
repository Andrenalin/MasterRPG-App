// @copyright André Trettin

import SwiftUI

public struct SheetFirstRootEditorView<LinkType: LinkDataTransferable>: View {
    public init(root: ItemRootController, linkControllable: any LinkControllable, model: any ItemDataAccessable, module: NetworkModules, headerTitle: String, linkTypes: LinkType.Type) {
        self.root = root
        let rootLinkControllable = linkControllable.rootManager.adventureRoot.linkControllable
        self.linkControllable = rootLinkControllable
        self.model = model
        self.module = module
        self.headerTitle = headerTitle
        self.linkTypes = linkTypes
        self._sheetRootModel = State(wrappedValue: SheetRootModel(linkControllable: root.linkControllable, sheetControllable: root.sheetControllable, itemId: model.id))
//        self._sheetRootModel = State(wrappedValue: TableFirstSheetModel(linkControllable: rootLinkControllable, parent: nil, model: model, level: 0, module: module))

    }
    
    let root: ItemRootController
    let linkControllable: LinkControllable
    let model: any ItemDataAccessable
    let module: NetworkModules
    let headerTitle: String
    let linkTypes: LinkType.Type
    
    @State private var sheetRootModel: SheetRootModel
//    @State private var sheetRootModel: TableFirstSheetModel

    public var body: some View {
        Section {
            SheetRootView(root: root, rootModel: sheetRootModel, isEditor: true, linkTypes: linkTypes)
//            SheetFirstView(root: root, model: sheetRootModel, isEditor: true, linkTypes: linkTypes)
        } header: {
            Text(headerTitle)
        }
//        .onChange(of: model.id) {
//            sheetRootModel.update(with: model)
//        }
//        .onChange(of: sheetRootModel.hasAnyChanges(for: sheetRootModel.sheetModel.source)) {
//            sheetRootModel.update(with: model)
//        }
    }
}
