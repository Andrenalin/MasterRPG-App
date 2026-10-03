// @copyright André Trettin

import SwiftUI

/// The shared skeleton every module's own `DetailFolderListView` wraps
/// `ItemDetailRootView` + `.openFileWindowOverlay` around identically — only
/// the editor content, per-item viewer, and `configuration`/`linkTypes`
/// actually vary per module (see each module's own `View/DetailFolderListView.swift`,
/// which stays the thin, module-typed entry point views/previews construct).
/// The optional bottom bar (Audio's player, Dice's roll result, Weather's overlay) is passed
/// through to `ItemDetailRootView`; without it those three modules bypassed this skeleton.
/// See CODE_AUDIT §9.3, CODE_AUDIT_Folder §9.5.
public struct DetailFolderList<Editor: View, Viewer: View, LinkTypes: LinkDataTransferable, BottomOverlayBar: View>: View {
    let root: any ItemRootControllable
    let openFileWindowModel: OpenFileWindowModel
    let detailListController: FolderListControllable
    let selectedModel: any ItemDataAccessible
    let configuration: ItemDetailConfiguration
    let linkTypes: LinkTypes.Type
    let showsBottomOverlayBar: Bool
    let bottomOverlayBarHeight: CGFloat?
    let bottomOverlayBar: () -> BottomOverlayBar
    let editor: () -> Editor
    let viewer: (UUID, @escaping () -> Void) -> Viewer

    public init(
        root: any ItemRootControllable,
        openFileWindowModel: OpenFileWindowModel,
        detailListController: FolderListControllable,
        selectedModel: any ItemDataAccessible,
        configuration: ItemDetailConfiguration = .init(),
        linkTypes: LinkTypes.Type,
        showsBottomOverlayBar: Bool = true,
        bottomOverlayBarHeight: CGFloat? = nil,
        @ViewBuilder bottomOverlayBar: @escaping () -> BottomOverlayBar = { EmptyView() },
        @ViewBuilder editor: @escaping () -> Editor,
        @ViewBuilder viewer: @escaping (UUID, @escaping () -> Void) -> Viewer
    ) {
        self.root = root
        self.openFileWindowModel = openFileWindowModel
        self.detailListController = detailListController
        self.selectedModel = selectedModel
        self.configuration = configuration
        self.linkTypes = linkTypes
        self.showsBottomOverlayBar = showsBottomOverlayBar
        self.bottomOverlayBarHeight = bottomOverlayBarHeight
        self.bottomOverlayBar = bottomOverlayBar
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
            showsBottomOverlayBar: showsBottomOverlayBar,
            bottomOverlayBarHeight: bottomOverlayBarHeight,
            bottomOverlayBar: bottomOverlayBar,
            editor: editor
        )
        .openFileWindowOverlay(openFileWindowModel, viewer: viewer)
    }
}
