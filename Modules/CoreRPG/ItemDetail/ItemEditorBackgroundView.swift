// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

struct ItemEditorBackgroundView<Editor: View>: View {
    let editor: Editor
    let model: any ItemDataAccessable
    let root: any ItemRootControllable
    let folderListController: FolderListControllable
    let fileTypes: [UTType]
    let shouldShowContent: Bool
    
    var body: some View {
        editor
            .id(model.id)
            .overlay(alignment: .bottom) {
                if !model.description.isEmpty {
                    GlassEffectContainerAll {
                        ItemDetailOverlayView(
                            model: model,
                            cacheItemListModel: root.editControllable.cacheItemListModel,
                            listDisplayModel: folderListController.listDisplayModel,
                            searchModel: folderListController.searchModel,
                            fullHeader: false,
                            onlyDescription: true,
                            lines: 3
                        )
                        .padding(6)
                        .padding(.horizontal)
#if !os(visionOS)
                        .glassEffectAll(.regular)
#endif
                    }
                    .padding()
                }
            }
            .overlay(alignment: .top) {
                if !model.specialCategory {
                    ItemFileImporterView(
                        root: root,
                        model: model,
                        fileTypes: fileTypes,
                        isInitial: false
                    )
                    .zIndex(10)
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .opacity(shouldShowContent ? 1 : 0)
            .allowsHitTesting(shouldShowContent)
            .accessibilityHidden(!shouldShowContent)
            .transition(.opacity)
    }
}

#Preview("Background Editor") {
    let fixture = FakeItemRootControllerFixture()
    ItemEditorBackgroundView(
        editor: Color.blue.opacity(0.2),
        model: FakeItemModel.empty,
        root: fixture.root,
        folderListController: fixture.folderListController,
        fileTypes: [],
        shouldShowContent: true
    )
}
