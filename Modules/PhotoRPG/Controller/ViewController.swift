// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    public let fileImporterViewType: FileImporterViewType = .custom
    public let goupViewType: GroupViewType = .photo
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {
    @MainActor public func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView {
        AnyView(PhotoInlineImporterView(itemId: itemId, preopen: preopen, layoutDown: layoutDown))
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func dropSelectionView(model: ItemSelectionModel) -> some View {
        DropChooseView(selectionModel: model)
            .environment(model)
    }
    
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }
    
    @ViewBuilder @MainActor func thumbnailRow(root: PhotoRootModel, for itemId: UUID) -> some View {
        if let model = root.itemController.itemSync(for: itemId), let cacheController = root.cacheController {
            ThumbnailRowPhotoView(cacheController: cacheController, model: model)
                .environment(root.editController.cacheItemListModel)
                .environment(root.listDisplayModel)
        }
    }

    @ViewBuilder @MainActor func photoRow(root: PhotoRootModel, for itemId: UUID) -> some View {
        if let model = root.itemController.itemSync(for: itemId), let cacheController = root.cacheController {
            CachePhotoView(cacheController: cacheController, model: model, highResolution: true)
                .environment(root.editController.cacheItemListModel)
        }
    }

    @MainActor func inlineViewer(root: PhotoRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return ViewerRootView(model: model, dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: PhotoRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return ViewerRootView(model: model, windowMode: true)
    }
    
    @MainActor func gameView(root: PhotoRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
    }
    
    @MainActor
    func gamePhotoView(root: PhotoRootModel) -> some View {
        ViewerRootView(model: root.gameController.currentItem(), toolBarModel: root.rootModel.toolbarModel, isGame: true)
            .environment(root)
    }
}

// MARK: - old

extension ViewController {
    @MainActor
    static let selectionTabId = UUID(uuidString: "249CC695-F7E5-408F-80F0-E8AD547063A4")!
}

// MARK: - Edit

public extension ViewController {
    @MainActor
    func detailEditor(root: PhotoRootModel, for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        PhotoDetailViewer(item: item)
            .environment(root)
    }

    @MainActor
    func onMapView(root: PhotoRootModel, photoId: UUID?, color: Color, size: CGSize, isDragging: Bool, isSelected: Bool) -> some View {
        OnMapPin(model: root.itemController.itemOrEmpty(for: photoId ?? UUID()), color: color, size: size, isDragging: isDragging, isSelected: isSelected)
            .environment(root)
    }
}

// MARK: - Game
public extension ViewController {
    @MainActor
    func gameToolBarView(root: PhotoRootModel) -> some View {
        GameToolBar(model: root.rootModel.toolbarModel, hideCloseButton: true, dismiss: nil)
    }

    @MainActor
    func mapImage(root: PhotoRootModel, for itemId: UUID?, size: CGSize, color: Color) -> some View {
        AsyncThumbnail(model: root.gameController.gameItem(for: itemId ?? UUID()), size: size, color: color)
            .environment(root)
    }
}

// MARK: - Selection

public extension ViewController {
    @MainActor
    func inlinePhotoSelectionButton(root: PhotoRootModel, editController: any EditControllable, photoId: Binding<UUID?>, entryId: UUID, showSelector: Binding<UUID?>) -> some View {
        InlinePhotoSelectionRow(editController: editController, photoId: photoId, entryId: entryId, showSelector: showSelector)
            .environment(root)
    }
    
    @MainActor
    func photoSelection(root: PhotoRootModel, editController: any EditControllable, selectionModel: SelectionModel, inline: Bool = false) -> some View {
        PhotoSelection(editController: editController, selectionModel: selectionModel, inline: inline)
    }

    @MainActor
    func photosSelection<Action: View>(root: PhotoRootModel, editController: any EditControllable, model: Binding<[UUID]>, selected: Binding<UUID?>? = nil, filter: ItemListCategory, @ViewBuilder actionView: @escaping () -> Action, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void) -> some View {
        PhotosSelection(editController: editController, model: model, selected: selected, filter: filter, selection: selection, toggleSelection: toggleSelection, actionView: actionView)
            .environment(root)
    }

    @MainActor
    func photosSelection(root: PhotoRootModel, editController: any EditControllable, model: Binding<[UUID]>, selected: Binding<UUID?>? = nil, filter: ItemListCategory, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void) -> some View {
        photosSelection(root: root, editController: editController, model: model, selected: selected, filter: filter, actionView: { EmptyView() }, selection: selection, toggleSelection: toggleSelection)
    }

    @MainActor
    func viewSelect(root: PhotoRootModel, filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: true, focus: nil, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        return RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true, modalDismissAction: dismissAction)
            .environment(root)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor
    func photoDetailView(root: PhotoRootModel, for itemId: UUID?, useGame: Bool, size: CGSize, contentMode: ContentMode = .fit) -> some View {
        let id = itemId ?? UUID()
        let model = useGame ? root.gameController.gameItem(for: id) : root.itemController.itemOrEmpty(for: id)
        return AsyncPhotoViewer(model: model, size: size, contentMode: contentMode)
            .environment(root)
    }

    @MainActor
    func rowView(root: PhotoRootModel, item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        PhotoRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }

    @MainActor
    func thumbnailView(root: PhotoRootModel, with id: UUID?, size: CGSize = PhotoRootModel.thumbnailSize, highResolution: Bool = false, radius: CGFloat = .init(8), ratio: ContentMode = .fill) -> some View {
        ThumbnailItem(root: root, model: root.itemController.itemOrEmpty(for: id ?? UUID()), size: size, radius: radius, ratio: ratio, highResolution: highResolution)
            .environment(root)
    }

    @MainActor
    func headerView(root: PhotoRootModel, id: UUID?, size: CGSize, topMargin: CGFloat) -> some View {
        AsyncHeaderPhoto(model: root.itemController.itemOrEmpty(for: id ?? UUID()), id: id, size: size, topMargin: topMargin)
            .environment(root)
    }
}
