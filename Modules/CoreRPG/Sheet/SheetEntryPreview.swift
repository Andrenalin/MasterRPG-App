// @copyright André Trettin

import SwiftUI

struct SheetEntryPreview: View {
    @Namespace private var namespace

    var body: some View {
        SheetEntryView(
            rootModel: .fake,
            parentModel: .empty,
            entryModel: .empty,
            isEditor: true,
            linkTypes: EmptyLinkTransferable.self,
            generatedAcceptanceNamespace: namespace,
            detailContent: { _ in EmptyView() }
        )
    }
}

#Preview {
    SheetEntryPreview()
}
