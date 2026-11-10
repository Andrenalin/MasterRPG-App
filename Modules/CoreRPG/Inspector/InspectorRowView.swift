// @copyright André Trettin

import SwiftUI

struct InspectorRowView: View {
    let root: any ItemRootControllable
    let item: FolderListItemModel
    let selectionModel: ItemSelectionModel
    let type: LinkRootType
    let showListModeControls: Bool

    @Binding var showDetails: Bool
    @Binding var showDetailsView: (any NavigationDestination)?

    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.itemGenerationAction) private var itemGenerationAction
    @Environment(\.generateMapAction) private var generateMapAction

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        let model = item.model

        HStack(spacing: 0) {
            rowContent(model: model)
                .selectListItem(isActive: isSelectionActive(model: model)) {
                    selectionModel.toggleSelection(
                        itemId: item.source.itemId,
                        entryId: item.source.entryId,
                        isCollection: model?.specialCategory ?? false
                    )
                } isSelected: {
                    selectionModel.selection.contains(where: {
                        $0.itemId == item.source.itemId && $0.entryId == item.source.entryId
                    })
                }
        }
        .padding(.leading, CGFloat(item.level * 4 + 8))
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundForLevel(item.level))
        .contentShape(.rect)
    }

    @ViewBuilder
    private func rowContent(model: (any ItemDataAccessible)?) -> some View {
        if let entryId = item.source.entryId, item.isEntryRow {
            entryRow(model: model, entryId: entryId)
        } else {
            standardItemRow(model: model)
        }
    }

    private func entryRow(model: (any ItemDataAccessible)?, entryId: UUID) -> some View {
        HStack {
            LinkEntryRowView(root: root, item: item, listDisplayModel: root.folderLinkControllable.listDisplayModel)
            InspectorRowViewFolderChevronView(root: root, item: item)
        }
        .contextMenu { rowContextMenu(model: model) }
        .accessibilityAction(named: Text("Open Details", bundle: .module)) {
            openDetail(model: model)
        }
        .draggableWithOverlay(
            for: root.configurable.module,
            itemId: item.source.itemId,
            entryId: entryId,
            name: model?[entryId].name.withoutLink() ?? ""
        )
    }

    private func standardItemRow(model: (any ItemDataAccessible)?) -> some View {
        itemRowView(model: model)
            .onTapGesture(count: 2) { openDetail(model: model) }
#if os(macOS)
            .onKeyPress(.return, phases: .down) { _ in
                openDetail(model: model)
                return .handled
            }
#endif
            .accessibilityHint(Text("Double-tap to open details", bundle: .module))
            .accessibilityAction(named: Text("Open Details", bundle: .module)) {
                openDetail(model: model)
            }
            .contextMenu { rowContextMenu(model: model) }
    }

    private func itemRowView(model: (any ItemDataAccessible)?) -> some View {
        let resolved = model ?? root.itemControllable.itemOrEmpty(for: item.source.itemId)
        return ItemRowView(
            root: root,
            model: resolved,
            cacheItemListModel: root.folderLinkControllable.cacheListItemModel,
            listDisplayModel: root.folderLinkControllable.listDisplayModel,
            searchModel: root.folderLinkControllable.searchModel,
            isSelected: false
        ) {
            if root.viewControllable.thumbnailRowViewType == .custom {
                root.viewControllable.thumbnailRowView(for: item.source.itemId)
            } else if root.viewControllable.thumbnailRowViewType == .photo,
                      let cacheController = root.cacheControllable {
                ThumbnailRowPhotoView(
                    cacheController: cacheController,
                    model: resolved,
                    listDisplayModel: root.folderLinkControllable.listDisplayModel
                )
            }
        }
        .draggableWithOverlay(
            for: selectionModel.onlyEntrySelection ? .none : root.configurable.module,
            itemId: item.source.itemId,
            entryId: nil,
            name: resolved.name.withoutLink()
        )
        .overlay(alignment: .trailing) {
            // The chevron of a regular item reveals its entries, which a list that does not
            // show entries leaves out; a folder or collection reveals items.
            if resolved.specialCategory || selectionModel.showsEntries(in: type, module: root.configurable.module) {
                InspectorRowViewFolderChevronView(root: root, item: item)
            }
        }
    }

    private func isSelectionActive(model: (any ItemDataAccessible)?) -> Bool {
        type.isSelection &&
        selectionModel.canSelect(
            isCollection: model?.specialCategory ?? false,
            entryId: item.source.entryId
        )
    }

    private func openDetail(model: (any ItemDataAccessible)?) {
#if os(macOS)
        guard model?.specialCategory != true else { return }
        scenesManager.openWindow(
            SceneId.viewerId(for: root.configurable.module),
            selection: WindowItemSelection(itemId: item.source.itemId)
        )
#else
        if model?.specialCategory == true {
            showDetailsView = root.folderLinkControllable.detailDestination(for: item.source.itemId)
        } else {
            showDetailsView = root.folderLinkControllable.viewerDestination(for: item.source.itemId)
        }
        showDetails.toggle()
#endif
    }

    @ViewBuilder
    private func rowContextMenu(model: (any ItemDataAccessible)?) -> some View {
        Button {
            openDetail(model: model)
        } label: {
            Label { Text("Open Details", bundle: .module) } icon: { Image(systemName: "arrow.up.right.square") }
        }
        
        if canGenerate(model: model) {
            generateItemView(model: model)
        }

        if canGenerateMap(model: model) {
            generateMapView(model: model)
        }

        ControlGroup {
            CompactDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
            MediumDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
            RegularDisplayModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
        }

        if showListModeControls {
            ControlGroup {
                ListModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
                FolderModeToggle(listDisplayModel: root.folderLinkControllable.listDisplayModel)
            }
        }

        if item.source.entryId != nil {
            Button {
                withAnimation { root.folderLinkControllable.toggleParentFolder(item: item) }
            } label: {
                Label {
                    Text("Close Parent Folder", bundle: .module)
                } icon: {
                    Image(systemName: "folder.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func backgroundForLevel(_ level: Int) -> some View {
        if level > 0 {
            if level % 2 == 1 {
                Color.secondary.opacity(0.2)
            } else {
                Color.primary.opacity(0.2)
            }
        }
    }
    
    func canGenerate(model: (any ItemDataAccessible)?) -> Bool {
        guard itemGenerationAction.isEnabled, let model else { return false }
        return root.configurable.module == .table && !model.specialCategory
    }

    /// Only a photo item (not an entry row, folder or collection) of a running game.
    func canGenerateMap(model: (any ItemDataAccessible)?) -> Bool {
        guard generateMapAction.isEnabled,
              root.configurable.module == .photo,
              root.itemControllable.itemDataModel.isGameMode,
              item.source.entryId == nil,
              let model else { return false }
        return !model.specialCategory
    }

    func generateMapView(model: (any ItemDataAccessible)?) -> some View {
        Button {
            guard let model else { return }
            generateMapAction(photoId: model.id)
        } label: {
            Label {
                Text("Generate Map", bundle: .module)
            } icon: {
                Image(systemName: "map")
            }
        }
    }

    func generateItemView(model: (any ItemDataAccessible)?) -> some View {
        Button {
            guard let model else { return }
            itemGenerationAction(model.id)
        } label: {
            Label {
                Text("Generate from \(model?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "gear")
            }
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct InspectorRowViewFolderChevronView: View {
    let root: any ItemRootControllable
    let item: FolderListItemModel

    @ViewBuilder
    var body: some View {
        if item.canOpen || item.isOpen || item.wasExplicitlyClosed {
            Button {
                root.folderLinkControllable.toggleFolder(item: item)
            } label: {
                Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.red)
                    .contentShape(.circle)
                    .frame(minWidth: 44, minHeight: 44)
#if !os(visionOS)
                    .glassEffect(.clear.interactive())
#endif
            }
            .borderLessTVButtonStyle()
            .accessibilityLabel(Text("Toggle Folder", bundle: .module))
            .padding(.trailing, 4)
        }
    }
}

#Preview {
    let item = {
        let item = FolderListItemModel(
            id: .fixture1,
            source: ItemRowModel(itemId: .fixture2, typeId: .none),
            level: 0,
            isShown: true
        )
        item.model = FakeItemModel(
            id: .fixture2,
            name: "Goblin Ambush",
            description: "A deterministic inspector row.",
            entries: []
        )
        return item
    }()
    InspectorRowView(
        root: ItemRootController.fake,
        item: item,
        selectionModel: ItemSelectionModel(),
        type: .inspector,
        showListModeControls: true,
        showDetails: .constant(false),
        showDetailsView: .constant(nil)
    )
    .environment(ScenesManager())
    .environment(AppGameStateModel())
}
