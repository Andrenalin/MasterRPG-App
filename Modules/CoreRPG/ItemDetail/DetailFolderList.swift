// @copyright André Trettin

import SwiftUI

/// The shared skeleton every module's own `DetailFolderListView` wraps
/// `ItemDetailRootView` + `.openFileWindowOverlay` around identically — only
/// the editor content, per-item viewer, and `configuration`/`linkTypes`
/// actually vary per module (see each module's own `View/DetailFolderListView.swift`,
/// which stays the thin, module-typed entry point views/previews construct).
/// See CODE_AUDIT §9.3.
public struct DetailFolderList<Editor: View, Viewer: View, LinkTypes: LinkDataTransferable>: View {
    let root: any ItemRootControllable
    let openFileWindowModel: OpenFileWindowModel
    let detailListController: FolderListControllable
    let selectedModel: any ItemDataAccessible
    let configuration: ItemDetailConfiguration
    let linkTypes: LinkTypes.Type
    let editor: () -> Editor
    let viewer: (UUID, @escaping () -> Void) -> Viewer

    public init(
        root: any ItemRootControllable,
        openFileWindowModel: OpenFileWindowModel,
        detailListController: FolderListControllable,
        selectedModel: any ItemDataAccessible,
        configuration: ItemDetailConfiguration = .init(),
        linkTypes: LinkTypes.Type,
        @ViewBuilder editor: @escaping () -> Editor,
        @ViewBuilder viewer: @escaping (UUID, @escaping () -> Void) -> Viewer
    ) {
        self.root = root
        self.openFileWindowModel = openFileWindowModel
        self.detailListController = detailListController
        self.selectedModel = selectedModel
        self.configuration = configuration
        self.linkTypes = linkTypes
        self.editor = editor
        self.viewer = viewer
    }

    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        ItemDetailRootView(
            root: root,
            detailListController: detailListController,
            selectedModel: selectedModel,
            configuration: configuration,
            linkTypes: linkTypes,
            editor: editor
        )
        .openFileWindowOverlay(openFileWindowModel, viewer: viewer)
    }
}
