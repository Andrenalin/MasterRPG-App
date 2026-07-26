// @copyright André Trettin

import SwiftUI

struct SheetViewPreview: View {
    @Namespace private var namespace
    private let fixture = FakeItemRootControllerFixture()

    private var rootSheetModel: SheetModel { fixture.sheetRootModel.sheetModel }
    private var firstEntry: SheetModel { rootSheetModel.entries.first ?? .empty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                SheetView(
                    root: fixture.root,
                    rootModel: fixture.sheetRootModel,
                    sheetModel: rootSheetModel,
                    isEditor: true,
                    linkTypes: EmptyLinkTransferable.self,
                    generatedAcceptanceNamespace: namespace,
                    detailContent: { _ in EmptyView() }
                )
                GeneratedSheetEntryTreeView(
                    rootModel: fixture.sheetRootModel,
                    parentModel: rootSheetModel,
                    entryModel: firstEntry,
                    isEditor: true,
                    linkTypes: EmptyLinkTransferable.self,
                    generatedAcceptanceNamespace: namespace,
                    detailAction: nil,
                    detailContent: { _ in EmptyView() }
                )
            }
            .padding()
        }
    }
}

#Preview {
    SheetViewPreview()
        .environment(AppGameStateModel())
}
