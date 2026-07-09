// @copyright André Trettin

import SwiftUI

public struct SheetRootView<LinkType: LinkDataTransferable, DetailContent: View>: View {
    public init(
        root: ItemRootController,
        rootModel: SheetRootModel,
        isEditor: Bool = false,
        linkTypes: LinkType.Type = LinkDiceData.self,
        detailAction: ((SheetModel) -> Void)? = nil
    ) where DetailContent == EmptyView {
        self.init(
            root: root,
            rootModel: rootModel,
            isEditor: isEditor,
            linkTypes: linkTypes,
            detailAction: detailAction,
            detailContent: { _ in EmptyView() }
        )
    }

    public init(
        root: ItemRootController,
        rootModel: SheetRootModel,
        isEditor: Bool = false,
        linkTypes: LinkType.Type = LinkDiceData.self,
        detailAction: ((SheetModel) -> Void)? = nil,
        @ViewBuilder detailContent: @escaping (SheetModel) -> DetailContent
    ) {
        self.root = root
        self.rootModel = rootModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
        self.detailAction = detailAction
        self.detailContent = detailContent
    }
    
    let root: ItemRootController
    let rootModel: SheetRootModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    let detailAction: ((SheetModel) -> Void)?
    let detailContent: (SheetModel) -> DetailContent
        
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        SheetView(root: root, rootModel: rootModel, sheetModel: rootModel.sheetModel, isEditor: isEditor, linkTypes: linkTypes, detailAction: detailAction, detailContent: detailContent)
            .id(rootModel.sheetModel.id)
            .focusedSceneValue(\.selectedSheetEntry, rootModel.selectedSheetEntryFocusValue)
    }
}
