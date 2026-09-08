// @copyright André Trettin

import SwiftUI

struct TableSheetView: View {
    let root: ItemRootController
    let model: SheetRootModel
    var addSearchable: Bool = true

    @Environment(SearchBarVisibleModel.self) private var searchBarVisibleModel

    @State private var scrollPosition = ScrollPosition(idType: UUID.self)

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        @Bindable var model = model

        TableSheetListContentView(root: root, model: model, scrollPosition: $scrollPosition)
            .applyIf(addSearchable && searchBarVisibleModel.isVisible) {
                $0.searchable(text: $model.searchText, placement: .automatic, prompt: Text("Find in", bundle: .module))
            }
    }
}

/// The scrollable recursive sheet body plus its scroll-to-entry handling.
private struct TableSheetListContentView: View {
    let root: ItemRootController
    let model: SheetRootModel
    @Binding var scrollPosition: ScrollPosition

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                SheetRootView(root: root, rootModel: model)
                    .animation(accessibilityReduceMotion ? nil : .default, value: model.searchText)
            }
        }
        .scrollPosition($scrollPosition, anchor: .center)
        .onChange(of: model.editorModel.scrollEntryId) { _, entryId in
            guard let entryId else { return }
            withAnimation(accessibilityReduceMotion ? nil : .smooth, completionCriteria: .logicallyComplete) {
                scrollPosition.scrollTo(id: entryId, anchor: .center)
            } completion: {
                // See ItemEditorForegroundView's matching comment: `.scrollPosition(_:anchor:)`
                // keeps re-centering on this id for any later layout change unless released.
                scrollPosition = ScrollPosition(idType: UUID.self)
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
    TableSheetView(root: ItemRootController.fake,
        model: .fake)
    .environment(AppWindowSizeModel())
    .environment(AppGameStateModel())
    .environment(ScenesManager())
    .environment(AppFocusModel())
    .environment(SearchBarVisibleModel())

}
