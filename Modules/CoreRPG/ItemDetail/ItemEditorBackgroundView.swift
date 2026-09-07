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
    /// Layers the editor above the file-importer/description overlays instead
    /// of beneath them, padded clear of the top overlay. RealityView-backed
    /// editors (SpaceRPG on visionOS) have real depth, so a flat overlay drawn
    /// "in front of" one in the view tree doesn't reliably stay visually in
    /// front — the model can protrude past the overlay's plane. Putting the
    /// editor on top instead, with room carved out at the top for the
    /// importer, avoids that collision rather than fighting it.
    var editorOnTop: Bool = false

    var body: some View {
        Group {
            if editorOnTop {
                OverlaysBaseView(model: model, root: root, folderListController: folderListController, fileTypes: fileTypes)
                    .overlay(alignment: .top) {
                        editor
                            .id(model.id)
                            .padding(.top, editorTopInset)
                    }
            } else {
                editor
                    .id(model.id)
                    .overlay(alignment: .bottom) {
                        DescriptionOverlayView(model: model, root: root, folderListController: folderListController)
                    }
                    .overlay(alignment: .top) {
                        FileImporterOverlayView(root: root, model: model, fileTypes: fileTypes)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(shouldShowContent ? 1 : 0)
        .allowsHitTesting(shouldShowContent)
        .accessibilityHidden(!shouldShowContent)
        .transition(.opacity)
    }

    private var editorTopInset: CGFloat { 96 }
}

private struct OverlaysBaseView: View {
    let model: any ItemDataAccessable
    let root: any ItemRootControllable
    let folderListController: FolderListControllable
    let fileTypes: [UTType]

    var body: some View {
        Color.clear
            .overlay(alignment: .bottom) {
                DescriptionOverlayView(model: model, root: root, folderListController: folderListController)
            }
            .overlay(alignment: .top) {
                FileImporterOverlayView(root: root, model: model, fileTypes: fileTypes)
            }
    }
}

private struct DescriptionOverlayView: View {
    let model: any ItemDataAccessable
    let root: any ItemRootControllable
    let folderListController: FolderListControllable

    var body: some View {
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
}

private struct FileImporterOverlayView: View {
    let root: any ItemRootControllable
    let model: any ItemDataAccessable
    let fileTypes: [UTType]

    var body: some View {
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
