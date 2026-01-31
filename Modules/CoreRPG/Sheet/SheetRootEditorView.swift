// @copyright André Trettin

import SwiftUI

public struct SheetRootEditorView<LinkType: LinkDataTransferable>: View {
    public init(root: ItemRootController, linkControllable: any LinkControllable, model: any ItemDataAccessable, module: NetworkModules, headerTitle: String, linkTypes: LinkType.Type) {
        self.root = root
        self.linkControllable = linkControllable
        self.model = model
        self.module = module
        self.headerTitle = headerTitle
        self.linkTypes = linkTypes
        self._tableSheetModel = State(wrappedValue: TableSheetModel(linkControllable: linkControllable, parent: nil, model: model, level: 0, module: module))
    }
    
    let root: ItemRootController
    let linkControllable: LinkControllable
    let model: any ItemDataAccessable
    let module: NetworkModules
    let headerTitle: String
    let linkTypes: LinkType.Type
    
    @State private var tableSheetModel: TableSheetModel
    
    public var body: some View {
        Section {
            SheetView(root: root, model: tableSheetModel, isEditor: true, linkTypes: linkTypes)
        } header: {
            Text(headerTitle)
        }
        .onChange(of: model.id) {
            tableSheetModel = TableSheetModel(linkControllable: linkControllable, parent: nil, model: model, level: 0, module: module)
        }
    }
}
