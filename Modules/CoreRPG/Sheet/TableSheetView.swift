// @copyright André Trettin

import SwiftUI

struct TableSheetView<LinkType: LinkDataTransferable>: View {
    init(
        root: ItemRootController,
        model: SheetRootModel,
        addSearchable: Bool = true,
        isEditor: Bool,
        linkTypes: LinkType.Type
    ) {
        self.root = root
        self.model = model
        self.addSearchable = addSearchable
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let root: ItemRootController
    let model: SheetRootModel
    var addSearchable: Bool = true
    let isEditor: Bool
    let linkTypes: LinkType.Type

    @State private var scrollPosition = ScrollPosition(idType: UUID.self)

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        @Bindable var model = model

        listContentView
            .applyIf(addSearchable) {
                $0.searchable(text: $model.searchText, placement: .toolbarPrincipalAll, prompt: Text("Find in", bundle: .module))
            }
    }
}

private extension TableSheetView {
    var listContentView: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                SheetRootView(
                    root: root,
                    rootModel: model,
                    isEditor: isEditor,
                    linkTypes: linkTypes
                )
                    .animation(accessibilityReduceMotion ? nil : .default, value: model.searchText)
            }
            .scrollTargetLayout()
        }
        .scrollPosition($scrollPosition, anchor: .center)
        .onChange(of: model.editorModel.scrollEntryId) { _, entryID in
            guard let entryID else { return }
            withAnimation(accessibilityReduceMotion ? nil : .smooth) {
                scrollPosition.scrollTo(id: entryID, anchor: .center)
            }
            model.editorModel.scrollEntryId = nil
        }
#if os(iOS)
        .background(theme.tint(for: root.configurable.module).opacity(0.3).gradient)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
#endif
        .toolbarTitleDisplayMode(.inline)
        .contentMargins(.horizontal, 8, for: .scrollContent)
    }
}

#Preview {
    TableSheetView(
        root: ItemRootController.fake,
        model: .fake,
        isEditor: false,
        linkTypes: LinkDiceData.self
    )
    .environment(AppWindowSizeModel())
    .environment(AppGameStateModel())
    .environment(ScenesManager())

}
