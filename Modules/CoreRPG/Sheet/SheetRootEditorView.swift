// @copyright André Trettin

import SwiftUI

public struct SheetRootEditorView<LinkType: LinkDataTransferable>: View {
    public init(root: ItemRootController, linkControllable: any LinkControllable, editorModel: SheetEditorModel, model: any ItemDataAccessable, module: NetworkModules, headerTitle: String, linkTypes: LinkType.Type) {
        self.root = root
        let rootLinkControllable = linkControllable.rootManager.adventureRoot.linkControllable
        self.linkControllable = rootLinkControllable
        self.model = model
        self.module = module
        self.headerTitle = headerTitle
        self.linkTypes = linkTypes
        self._sheetRootModel = State(wrappedValue: SheetRootModel(linkControllable: root.linkControllable, sheetControllable: root.sheetControllable, itemId: model.id, isEditor: true, editorModel: editorModel))
    }
    
    let root: ItemRootController
    let linkControllable: LinkControllable
    let model: any ItemDataAccessable
    let module: NetworkModules
    let headerTitle: String
    let linkTypes: LinkType.Type
    
    @State private var sheetRootModel: SheetRootModel

    public var body: some View {
        Section {
            SheetRootView(root: root, rootModel: sheetRootModel, isEditor: true, linkTypes: linkTypes)
        } header: {
            Text(headerTitle)
        }
    }
}
