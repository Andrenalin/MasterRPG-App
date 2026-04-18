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
        self._tableFSheetModel = State(wrappedValue: TableFirstSheetModel(linkControllable: rootLinkControllable, parent: nil, model: model, level: 0, module: module))
    }
    
    let root: ItemRootController
    let linkControllable: LinkControllable
    let model: any ItemDataAccessable
    let module: NetworkModules
    let headerTitle: String
    let linkTypes: LinkType.Type
    
    @State private var tableFSheetModel: TableFirstSheetModel
    
    public var body: some View {
        Section {
            SheetFirstView(root: root, model: tableFSheetModel, isEditor: true, linkTypes: linkTypes)
        } header: {
            Text(headerTitle)
        }
        .onChange(of: model.id) {
            tableFSheetModel.update(with: model)
        }
        .onChange(of: tableFSheetModel.hasAnyChanges(for: tableFSheetModel.sheetModel.source)) {
            tableFSheetModel.update(with: model)
        }
    }
}
