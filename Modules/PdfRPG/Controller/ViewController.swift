// @copyright André Trettin

import AndrenalinKit
import SwiftUI

public struct ViewController {
    public let goupViewType: GroupViewType = .photo
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {}

// MARK: Viewer

public extension ViewController {
    @MainActor func linkWindow(root: PdfRootModel, isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
            .environment(root)
    }

    @MainActor func windowViewer(root: PdfRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return NavigationStack {
            PdfViewerView(model: model, entryId: selection.entryId, withoutBookmark: false)
        }
        .ignoresSafeArea()
        .navigationTitle(model.name)
        .environment(root)
    }

    @MainActor func inlineViewer(root: PdfRootModel, with id: UUID, withoutBookmark: Bool, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return PdfViewerView(model: model, entryId: nil, withoutBookmark: withoutBookmark, dismissAction: dismissAction)
            .environment(root)
    }
    
    @MainActor func selectionView(root: PdfRootModel, model: ItemSelectionModel) -> some View {
        LinkRootView(type: .selection)
            .environment(root)
    }
}

public extension ViewController {
    @MainActor
    func detailEditor(root: PdfRootModel, for item: ItemRowTreeModel, module: NetworkModules) -> some View {
        PdfDetailViewer(item: item)
            .environment(root)
    }

    @MainActor
    private static let gameTabId = UUID()

    @MainActor
    func gameView(root: PdfRootModel, select: Bool = false) -> some View {
        if select == true, let id = root.gameController.gameModel.currentItemId {
            let item = root.gameController.gameItem(for: id)
            if item.displayState == 0 {
                let model = ItemRowModel(itemId: id, typeId: .pdf)
                let _ = root.listController(tabId: ViewController.gameTabId, focus: model)
            }
        }
        return RootNaviList(root: root, tabId: ViewController.gameTabId)
            .itemSplitViewSizeMode(.small)
            .itemListChildrenConfiguration(canNavigate: false, disableSelection: true)
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
