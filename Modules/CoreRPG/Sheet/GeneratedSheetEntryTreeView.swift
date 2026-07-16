// @copyright André Trettin

import SwiftUI

struct GeneratedSheetEntryTreeView<LinkType: LinkDataTransferable, DetailContent: View>: View {
    init(
        rootModel: SheetRootModel,
        parentModel: SheetModel,
        entryModel: SheetModel,
        isEditor: Bool,
        linkTypes: LinkType.Type,
        generatedAcceptanceNamespace: Namespace.ID,
        detailAction: ((SheetModel) -> Void)?,
        @ViewBuilder detailContent: @escaping (SheetModel) -> DetailContent
    ) {
        self.rootModel = rootModel
        self.parentModel = parentModel
        self.entryModel = entryModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
        self.generatedAcceptanceNamespace = generatedAcceptanceNamespace
        self.detailAction = detailAction
        self.detailContent = detailContent
    }

    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    let generatedAcceptanceNamespace: Namespace.ID
    let detailAction: ((SheetModel) -> Void)?
    let detailContent: (SheetModel) -> DetailContent

    var body: some View {
        SheetEntryView(
            rootModel: rootModel,
            parentModel: parentModel,
            entryModel: entryModel,
            isEditor: isEditor,
            linkTypes: linkTypes,
            generatedAcceptanceNamespace: generatedAcceptanceNamespace,
            detailAction: detailAction,
            detailContent: detailContent
        )
        .frame(maxWidth: .infinity, alignment: .leading)

        ForEach(visibleChildEntries) { childEntry in
            if childEntry.isGeneratedAnswer {
                GeneratedSheetEntryTreeView(
                    rootModel: rootModel,
                    parentModel: entryModel,
                    entryModel: childEntry,
                    isEditor: isEditor,
                    linkTypes: linkTypes,
                    generatedAcceptanceNamespace: generatedAcceptanceNamespace,
                    detailAction: detailAction,
                    detailContent: detailContent
                )
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let root = rootModel.rootController(for: childEntry.source.typeId), childEntry.isShown {
                SheetView(
                    root: root,
                    rootModel: rootModel,
                    sheetModel: childEntry,
                    isEditor: isEditor,
                    linkTypes: linkTypes,
                    generatedAcceptanceNamespace: generatedAcceptanceNamespace,
                    detailAction: detailAction,
                    detailContent: detailContent
                )
                .padding(.leading, 2)
            }
        }
    }

    private var visibleChildEntries: [SheetModel] {
        entryModel.entries.filter { !$0.isHidden && !$0.isGeneratedHidden }
    }
}

#Preview("Generated Sheet Tree Direct") {
    @Previewable @Namespace var namespace
    GeneratedSheetEntryTreeView(
        rootModel: .fake,
        parentModel: .empty,
        entryModel: .empty,
        isEditor: true,
        linkTypes: EmptyLinkTransferable.self,
        generatedAcceptanceNamespace: namespace,
        detailAction: nil,
        detailContent: { _ in EmptyView() }
    )
}
