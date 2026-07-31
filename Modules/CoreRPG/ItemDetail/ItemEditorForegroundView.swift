// @copyright André Trettin

import SwiftUI

struct ItemEditorForegroundView<Editor: View>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let editor: Editor
    let model: any ItemDataAccessable
    let root: any ItemRootControllable
    let folderListController: FolderListControllable
    let shouldShowContent: Bool
    let isSubFolder: Bool

    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        Group {
            if model.specialCategory {
                specialCategoryContent
            } else {
                formEditorContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(shouldShowContent ? 1 : 0)
        .allowsHitTesting(shouldShowContent)
        .accessibilityHidden(!shouldShowContent)
        .transition(.scale)
    }
    
    @ViewBuilder
    private var specialCategoryContent: some View {
        ItemDetailOverlayView(
            model: model,
            cacheItemListModel: root.editControllable.cacheItemListModel,
            listDisplayModel: folderListController.listDisplayModel,
            searchModel: folderListController.searchModel,
            fullHeader: false,
            onlyDescription: true
        )
        .padding()
        
        ListRootView(
            root: root,
            listController: folderListController,
            parentModel: model,
            isSubFolder: isSubFolder
        )
        //.environment(folderListController.listDisplayModel)
    }
    
    private var formEditorContent: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if !model.description.isEmpty {
                    ItemDetailOverlayView(
                        model: model,
                        cacheItemListModel: root.editControllable.cacheItemListModel,
                        listDisplayModel: folderListController.listDisplayModel,
                        searchModel: folderListController.searchModel,
                        fullHeader: false,
                        onlyDescription: true
                    )
                }

                editor
            }
            .scrollTargetLayout()
            .padding()
        }
        .scrollPosition($scrollPosition, anchor: .center)
        .scrollClipDisabled(true)
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: root.editControllable.editorModel.sheetEditorModel.scrollEntryId) { _, entryID in
            guard let entryID else { return }
            withAnimation(accessibilityReduceMotion ? nil : .smooth) {
                scrollPosition.scrollTo(id: entryID, anchor: .center)
            }
            root.editControllable.editorModel.sheetEditorModel.scrollEntryId = nil
        }
    }
}

#Preview("Foreground Editor") {
    let fixture = FakeItemRootControllerFixture()
    ItemEditorForegroundView(
        editor: Text(verbatim: "Editor content"),
        model: FakeItemModel.empty,
        root: fixture.root,
        folderListController: fixture.folderListController,
        shouldShowContent: true,
        isSubFolder: false
    )
    .environment(AppFocusModel())
}
