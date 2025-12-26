// @copyright André Trettin

import SwiftUI

struct TableSheetView<ImageContent: View>: View {
    let root: ItemRootController
    let model: TableSheetModel
    let windowMode: Bool
    let dismissAction: (() -> Void)?
    let imageContent: (CGSize) -> ImageContent

    @Environment(\.appSizeMode) private var appSizeMode
    @Environment(\.dismiss) var dismiss
    @Environment(\.showGame) private var showGame

    var body: some View {
        @Bindable var model = model
        
        listContentView
            .searchable(text: $model.searchText, placement: .automatic, prompt: "Find in")
    }
}

private extension TableSheetView {
    var listContentView: some View {
        List {
            SheetView(root: root, model: model)
                .animation(.default, value: model.searchText)
        }
#if os(iOS)
        .background(root.configurable.module.tint.opacity(0.3).gradient)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .listRowSpacing(4)
#endif
        .toolbarTitleDisplayMode(.inline)
        .contentMargins(.horizontal, 8, for: .scrollContent)
    }
}

#Preview {
    TableSheetView(
        root: ItemRootController.fake,
        model: TableSheetModel(
            linkControllable: FakeLinkController.fake,
            sheetModel: SheetModel(
                source: ItemRowModel(itemId: UUID(), typeId: .table),
                level: 0,
                name: "Hallo",
                description: "More",
                entries: [
                    SheetModel(source: ItemRowModel(itemId: UUID(), entryId: UUID(), typeId: .table), level: 1, name: "First", description: "Mega mit Link [Name](RPG://PHOTOS/0/9D877C38-41F5-4595-93A4-C25DC94BDD2E)", entries: [
                        SheetModel(source: ItemRowModel(itemId: UUID(), typeId: .table), level: 2, name: "Entry", description: "Value of Entry", entries: []),
                        SheetModel(source: ItemRowModel(itemId: UUID(), typeId: .table), level: 2, name: "2nd Entry", description: "Another Value of Entry", entries: [])
                    ]),
                    SheetModel(source: ItemRowModel(itemId: UUID(), entryId: UUID(), typeId: .table), level: 1, name: "Second **Master**", description: "Here it comes more", entries: [
                        SheetModel(source: ItemRowModel(itemId: UUID(), typeId: .table), level: 2, name: "Entry", description: "Value [inside link](RPG://MAPS/0/2181D9D0-8896-44E0-B2C4-A6E93F2533D7) of Entry und  [Name](RPG://PHOTOS/0/9D877C38-41F5-4595-93A4-C25DC94BDD2E) noch einer", entries: []),
                        SheetModel(source: ItemRowModel(itemId: UUID(), typeId: .table), level: 2, name: "2nd Entry", description: "Another Value of Entry", entries: [])
                    ])
                ]
            ),
            searchText: "in"
        ),
        windowMode: true,
        dismissAction: nil,
        imageContent: { _ in Text("Empty")
        }
    )
}
