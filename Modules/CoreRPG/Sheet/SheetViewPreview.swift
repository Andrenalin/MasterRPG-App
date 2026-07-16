// @copyright André Trettin

import SwiftUI

struct SheetViewPreview: View {
    @Namespace private var namespace
    private let fixture = FakeItemRootControllerFixture()

    var body: some View {
        VStack {
            SheetView(
                root: fixture.root,
                rootModel: fixture.sheetRootModel,
                sheetModel: .empty,
                isEditor: true,
                linkTypes: EmptyLinkTransferable.self,
                generatedAcceptanceNamespace: namespace,
                detailContent: { _ in EmptyView() }
            )
            GeneratedSheetEntryTreeView(
                rootModel: fixture.sheetRootModel,
                parentModel: .empty,
                entryModel: .empty,
                isEditor: true,
                linkTypes: EmptyLinkTransferable.self,
                generatedAcceptanceNamespace: namespace,
                detailAction: nil,
                detailContent: { _ in EmptyView() }
            )
        }
    }
}

#Preview {
    SheetViewPreview()
}
