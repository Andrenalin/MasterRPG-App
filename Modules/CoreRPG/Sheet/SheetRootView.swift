// @copyright André Trettin

import SwiftUI

struct SheetRootView<LinkType: LinkDataTransferable>: View {
    init(root: ItemRootController, rootModel: SheetRootModel, isEditor: Bool = false, linkTypes: LinkType.Type = LinkDiceData.self) {
        self.root = root
        self.rootModel = rootModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }
    
    let root: ItemRootController
    let rootModel: SheetRootModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
        
    var body: some View {
        SheetView(root: root, rootModel: rootModel, sheetModel: rootModel.sheetModel, isEditor: isEditor, linkTypes: linkTypes)
    }
}
