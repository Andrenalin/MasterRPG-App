// @copyright André Trettin

import AndrenalinKit
import Observation
import SwiftUI

public struct ViewController {
    weak var root: PhotoRoot!
}


extension ViewController {
    @MainActor
    static let selectionTabId = UUID(uuidString: "249CC695-F7E5-408F-80F0-E8AD547063A4")!
}

// MARK: - Edit

public extension ViewController {
    @MainActor
    func detailEditor(for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        PhotoDetailViewer(item: item)
            .environment(root)
    }

    @MainActor
    func onMapView(photoId: UUID?, color: Color, size: CGSize, isDragging: Bool, isSelected: Bool) -> some View {
        OnMapPin(model: root.itemController.itemOrEmpty(for: photoId ?? UUID()), color: color, size: size, isDragging: isDragging, isSelected: isSelected)
            .environment(root)
    }
}

// MARK: - Game
public extension ViewController {
    @MainActor
    func gamePhotoView() -> some View {
        RootPhotoViewer(model: root.gameController.currentItem(), toolBarModel: root.rootModel.toolbarModel, isGame: true)
            .environment(root)
    }

    @MainActor
    func gameToolBarView() -> some View {
        GameToolBar(model: root.rootModel.toolbarModel, hideCloseButton: true, dismiss: nil)
    }

    @MainActor
    private static let gameTabId = UUID()

    @MainActor
    func gameView(select: Bool = false) -> some View {
        if select == true, let id = root.gameController.gameModel.currentItemId {
            let item = root.gameController.gameItem(for: id)
            if item.displayState == 0 {
                let model = ItemRowModel(itemId: id, typeId: root.itemController.itemDataModel.networkModule)
                let _ = root.listController(tabId: ViewController.gameTabId, focus: model)
            }
        }
        return RootNaviList(root: root, tabId: ViewController.gameTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false, disableSelection: true)
            .environment(root)
    }
    
    @MainActor
    func mapImage<Content: View>(for itemId: UUID?, size: CGSize, content: @escaping (AKImage?) -> Content) -> some View {
        AsyncThumbnail(model: root.gameController.gameItem(for: itemId ?? UUID()), size: size, content: content)
            .environment(root)
    }
}

// MARK: - Selection

public extension ViewController {
    @MainActor
    func inlinePhotoSelectionButton(editController: any EditControllable, photoId: Binding<UUID?>, entryId: UUID, showSelector: Binding<UUID?>) -> some View {
        InlinePhotoSelectionRow(editController: editController, photoId: photoId, entryId: entryId, showSelector: showSelector)
            .environment(root)
    }
    
    @MainActor
    func photoSelection(editController: any EditControllable, selectionModel: SelectionModel, inline: Bool = false) -> some View {
        PhotoSelection(editController: editController, selectionModel: selectionModel, inline: inline)
    }

    @MainActor
    func photosSelection<Action: View>(editController: any EditControllable, model: Binding<[UUID]>, selected: Binding<UUID?>? = nil, filter: ItemListCategory, @ViewBuilder actionView: @escaping () -> Action, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void) -> some View {
        PhotosSelection(editController: editController, model: model, selected: selected, filter: filter, selection: selection, toggleSelection: toggleSelection, actionView: actionView)
            .environment(root)
    }

    @MainActor
    func photosSelection(editController: any EditControllable, model: Binding<[UUID]>, selected: Binding<UUID?>? = nil, filter: ItemListCategory, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void) -> some View {
        photosSelection(editController: editController, model: model, selected: selected, filter: filter, actionView: { EmptyView() }, selection: selection, toggleSelection: toggleSelection)
    }

    @MainActor
    func viewSelect(filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: true, focus: nil, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        return RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true, modalDismissAction: dismissAction)
            .environment(root)
    }
}

// MARK: - Window

public extension ViewController {
    @MainActor
    private static let linkTabId = UUID()

    @MainActor
    func linkWindow() -> some View {
//        RootLinkWindow(editController: root.editController(type: .link), tabId: ViewController.linkTabId, selection: false)
        RootNaviList(root: root, tabId: ViewController.linkTabId)
            .itemSplitViewSizeMode(.small)
            .itemListConfiguration(canAdd: false)
            .itemListChildrenConfiguration(canNavigate: false)
            .focusedSceneValue(\.selectedModule, .constant(root.itemController.itemDataModel.networkModule))
            .environment(root)
            .environment(SelectionSheetLinkModel())
    }

    @MainActor
    func photoWindow(selection: ItemSelection) -> some View {
        RootPhotoViewer(model: root.itemController.itemOrEmpty(for: selection.itemId), toolBarModel: GameToolBarModel())
            .navigationTitle(root.itemController.itemOrEmpty(for: selection.itemId).name)
            .environment(root)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor
    func photoView<Content: View>(for itemId: UUID?, useGame: Bool, content: @escaping (AKImage, Double) -> Content) -> some View {
        let id = itemId ?? UUID()
        let model = useGame ? root.gameController.gameItem(for: id) : root.itemController.itemOrEmpty(for: id)
        return AsyncPhoto(model: model, content: content)
            .environment(root)
    }

    @MainActor
    func rowView(item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        PhotoRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }

    @MainActor
    func thumbnailView(with id: UUID?, size: CGSize = PhotoRoot.thumbnailSize, highResolution: Bool = false, radius: CGFloat = .init(8), ratio: ContentMode = .fill) -> some View {
        ThumbnailItem(root: root, model: root.itemController.itemOrEmpty(for: id ?? UUID()), size: size, radius: radius, ratio: ratio, highResolution: highResolution)
            .environment(root)
    }
    
    @MainActor 
    func headerView(with id: Binding<UUID?>, size: CGSize, topMargin: CGFloat) -> some View {
        Group {
            if let imageId = id.wrappedValue {
                AsyncPhoto(model: root.itemController.itemOrEmpty(for: imageId)) { image, degress in
                    HeaderPhoto(itemId: id, image: image, degrees: degress, size: size, topMargin: topMargin)
                }
            } else {
                HeaderPhoto(itemId: id, image: nil, degrees: 0, size: size, topMargin: topMargin)
            }
        }
        .environment(root)
    }
}
