// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    public let goupViewType: GroupViewType = .photo
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {}

// MARK: Viewer

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }

    @MainActor func inlineViewer(root: PdfRootModel, with id: UUID, withoutBookmark: Bool, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return PdfViewerView(model: model, entryId: nil, withoutBookmark: withoutBookmark, dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: PdfRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return PdfViewerView(model: model, entryId: selection.entryId, windowMode: true, withoutBookmark: false)
//        .ignoresSafeArea()
//        .navigationTitle(model.name)
    }
    
    @MainActor func gameView(root: PdfRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
    }
}

public extension ViewController {
    @MainActor
    func detailEditor(root: PdfRootModel, for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        PdfDetailViewer(item: item)
            .environment(root)
    }

    @MainActor
    func gamePdfView(root: PdfRootModel) -> some View {
        PdfViewerView(model: root.gameController.currentItem(), entryId: nil, withoutBookmark: true, dismissAction: nil)
            .padding(32)
            .padding(.top, 64)
            .environment(root)
            .environment(\.showGame, true)
    }
}

// MARK: Links

public extension ViewController {
    @MainActor
    private static let linkTabId = UUID()

    @MainActor
    func selectForScanning(root: PdfRootModel, model: SelectionModel) -> some View {
        PdfSelectionView(root: root, selectionModel: model)
    }
}

// MARK: Selection

public extension ViewController {
    @MainActor
    static let selectionTabId = UUID(uuidString: "55BDB18F-18CA-4900-B7FB-7EDD5F667FF9")!

    @MainActor
    func viewSelect(root: PdfRootModel, filter: ItemListCategory = .all, onlyItems: Bool = false, onlyEntries: Bool = false, selection: @escaping () -> [ItemRowModel], toggleSelection: @escaping (ItemRowModel, Bool) -> Void, dismissAction: @escaping () -> Void) -> some View {
        let listController = root.listController(tabId: ViewController.selectionTabId)
        listController.setSelection(onlyItems: onlyItems, onlyEntries: onlyEntries, filter: filter, isHidden: false, focus: nil, mode: SelectionMode(selected: selection, toggle: toggleSelection))
        return RootNaviList(root: root, tabId: ViewController.selectionTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false)
            .itemListConfiguration(modalOk: true, modalDismissAction: dismissAction)
            .environment(root)
    }
}

// MARK: Viewer

public extension ViewController {
    @MainActor
    func pdfWindow(root: PdfRootModel, selection: ItemSelection) -> some View {
        PdfViewerView(model: root.itemController.itemOrEmpty(for: selection.itemId), entryId: selection.entryId, withoutBookmark: false)
            .navigationTitle(root.itemController.itemOrEmpty(for: selection.itemId).name)
            .environment(root)
    }

    func rowView(root: PdfRootModel, item: ItemRowTreeModel, isSelected: Bool, cacheItemListModel: CacheItemListModel) -> some View {
        PdfRow(item: item, isSelected: isSelected, cacheItemListModel: cacheItemListModel)
            .environment(root)
    }

    @MainActor
    func viewPdfInline(root: PdfRootModel, with id: UUID, withoutBookmark: Bool, dismissAction: (() -> Void)? = nil) -> some View {
        PdfViewerView(model: root.itemController.itemOrEmpty(for: id), entryId: nil, withoutBookmark: withoutBookmark, dismissAction: dismissAction)
            .environment(root)
    }
}
