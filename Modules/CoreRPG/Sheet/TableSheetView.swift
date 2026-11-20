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
            .applyIf(showsSearchable) {
                $0.searchable(text: $model.searchText, placement: .automatic, prompt: Text("Find in", bundle: .module))
            }
    }
}

private extension TableSheetView {
    /// `applyIf` swaps the view's structure with its condition, which rebuilds everything below
    /// it: the scroll view, its position and the sheet. So the condition must not follow the game
    /// sidebar's visibility where the sheet stays mounted while hidden (iOS: the panel only
    /// slides out, and keeps its scroll position and navigation). Only macOS needs the flag,
    /// where a `.searchable` can outlive the removed sheet (see `SearchBarVisibleModel`).
    var showsSearchable: Bool {
#if os(macOS)
        addSearchable && searchBarVisibleModel.isVisible
#else
        addSearchable
#endif
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
            LazyVStack(spacing: 2) {
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
