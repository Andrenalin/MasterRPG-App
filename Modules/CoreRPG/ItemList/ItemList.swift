// @copyright André Trettin

import SwiftUI

public struct ItemList<Row: View, EditGroupView: View, ExportView: View, GeneratorView: View>: View {
    public init(listController: any ListControllable, @ViewBuilder row: @escaping (ItemRowTreeModel, Bool) -> Row, @ViewBuilder editGroupView: @escaping ([ItemRowTreeModel], Binding<Bool>) -> EditGroupView, @ViewBuilder exportView: @escaping ([ItemRowTreeModel], Binding<Bool>) -> ExportView, @ViewBuilder generatorView: @escaping (Binding<ItemRowModel?>) -> GeneratorView) {
        self.listController = listController
        self.rowView = row
        self.editGroupView = editGroupView
        self.exportView = exportView
        self.generatorView = generatorView
        self.exportDisabled = false
        self.generatorDisabled = false
        self.onlyList = false

        self._selectedItems = State(wrappedValue: Set(listController.model.selectedItems))
    }

    public init(listController: any ListControllable, @ViewBuilder row: @escaping (ItemRowTreeModel, Bool) -> Row, @ViewBuilder exportView: @escaping ([ItemRowTreeModel], Binding<Bool>) -> ExportView, @ViewBuilder generatorView: @escaping (Binding<ItemRowModel?>) -> GeneratorView) where EditGroupView == EmptyView {
        self.listController = listController
        self.rowView = row
        self.editGroupView = { _, _ in EmptyView() }
        self.exportView = exportView
        self.generatorView = generatorView
        self.exportDisabled = false
        self.generatorDisabled = false
        self.onlyList = false

        self._selectedItems = State(wrappedValue: Set(listController.model.selectedItems))
    }

    public init(listController: any ListControllable, @ViewBuilder rowView: @escaping (ItemRowTreeModel, Bool) -> Row, @ViewBuilder exportView: @escaping ([ItemRowTreeModel], Binding<Bool>) -> ExportView) where EditGroupView == EmptyView, GeneratorView == EmptyView {
        self.listController = listController
        self.rowView = rowView
        self.editGroupView = { _, _ in EmptyView() }
        self.exportView = exportView
        self.generatorView = { _ in EmptyView() }
        exportDisabled = false
        generatorDisabled = true
        onlyList = false

        self._selectedItems = State(wrappedValue: Set(listController.model.selectedItems))
    }

    public init(listController: any ListControllable, @ViewBuilder rowView: @escaping (ItemRowTreeModel, Bool) -> Row, @ViewBuilder editGroupView: @escaping ([ItemRowTreeModel], Binding<Bool>) -> EditGroupView, @ViewBuilder exportView: @escaping ([ItemRowTreeModel], Binding<Bool>) -> ExportView) where GeneratorView == EmptyView {
        self.listController = listController
        self.rowView = rowView
        self.editGroupView = editGroupView
        self.exportView = exportView
        self.generatorView = { _ in EmptyView() }
        exportDisabled = false
        generatorDisabled = true
        onlyList = false

        self._selectedItems = State(wrappedValue: Set(listController.model.selectedItems))
    }

    public init(listController: any ListControllable, @ViewBuilder rowView: @escaping (ItemRowTreeModel, Bool) -> Row) where EditGroupView == EmptyView, ExportView == EmptyView, GeneratorView == EmptyView {
        self.listController = listController
        self.rowView = rowView
        self.editGroupView = { _, _ in EmptyView() }
        self.exportView = { _, _ in EmptyView() }
        self.generatorView = { _ in EmptyView() }
        exportDisabled = true
        generatorDisabled = true
        onlyList = true

        self._selectedItems = State(wrappedValue: Set(listController.model.selectedItems))
    }

    let listController: any ListControllable
    let rowView: (ItemRowTreeModel, Bool) -> Row
    let editGroupView: ([ItemRowTreeModel], Binding<Bool>) -> EditGroupView
    let exportView: ([ItemRowTreeModel], Binding<Bool>) -> ExportView
    let generatorView: (Binding<ItemRowModel?>) -> GeneratorView

    let exportDisabled: Bool
    let generatorDisabled: Bool
    let onlyList: Bool

    @Environment(\.itemSplitViewSizeMode) private var sizeMode
    @Environment(\.itemListConfiguration) private var itemListConfiguration
    @Environment(\.itemListChildrenConfiguration) private var childrenConfiguration

#if os(iOS) || os(visionOS)
    @Environment(\.editMode) private var editMode
#endif

    @State private var selectedItems: Set<ItemRowTreeModel>
    @State private var isSearching: Bool = false

    // Context Menu
    @State private var showEditGroup: Bool = false
    @State private var showExport: Bool = false
    
    @State private var removeEntryList = RemoveEntryListModel()

    public var body: some View {
        @Bindable var itemListModel = listController.model
        ScrollViewReader { scrollProxy in
            if onlyList {
                listView(scrollProxy: scrollProxy)
            } else {
                listView(scrollProxy: scrollProxy)
#if !os(tvOS)
                    .applyIf(listController.model.allowEditing || (sizeMode != .small && !childrenConfiguration.disableSelection)) { content in
                        content
                            .contextMenu(forSelectionType: ItemRowTreeModel.self) { selection in
                                ItemListContextMenu(listController: listController, selection: selection, exportDisabled: exportDisabled, generatorDisabled: generatorDisabled, removeEntryList: removeEntryList, showEditGroup: $showEditGroup, showExport: $showExport)
                            }
                    }
                    .modifier(ItemListSearchableViewModifer(listController: listController))
                    .modifier(ItemListToolBarViewModifier(listController: listController, itemListConfiguration: itemListConfiguration, childrenConfiguration: childrenConfiguration))
                    .overlay {
                        if showExport {
                            exportView(listController.model.actionSelection , $showExport)
                        }
                        if itemListModel.showGeneratorItem != nil {
                            generatorView($itemListModel.showGeneratorItem)
                        }
                    }
#endif
#if os(macOS)
                    .onDeleteCommand {
                        guard let item = itemListModel.selectedItem else { return }
                        itemListModel.actionSelection = [item]
                        removeEntryList.removeItems = [item.model]
                        withAnimation { removeEntryList.showDeleteAlert.toggle() }
                    }
                    .onMoveCommand { direction in
                        selectItem(direction)
                    }
#endif
                    .sizedSheet(isPresented: $showEditGroup) {
                        editGroupView(listController.model.actionSelection, $showEditGroup)
                    }
                    .sizedSheet(isPresented: $removeEntryList.showDeleteAlert, idealSize: CGSize(width: 500, height: 800)) {
                        EffectedLinkAction(itemControllable: listController.itemControllable, removeEntryList: removeEntryList) { _ in
                            Task {
                                await listController.deleteItems(selection: Set(listController.model.actionSelection))
                            }
                        }
                    }
            }
        }
    }

    @MainActor
    private func listView(scrollProxy: ScrollViewProxy) -> some View {
        List(selection: $selectedItems) {
            ItemListSection(listController: listController, rowView: rowView, removeEntryList: removeEntryList)
        }
        .animation(nil, value: listController.model.allowEditing)
        .scrollIndicatorsFlash(onAppear: true)
        .scrollIndicatorsFlash(trigger: listController.model.filteredItems.count)
#if !os(visionOS)
        .scrollDismissesKeyboard(.immediately)
#endif
        .navigationTitle(listController.model.listTitleName)
#if os(iOS) || os(visionOS)
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(itemListConfiguration.modal && itemListConfiguration.inline ? .inline : .large)
#endif
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 300)
        .applyIf(itemListConfiguration.modal || itemListConfiguration.modalOk) { content in
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            withAnimation { itemListConfiguration.modalDismissAction() }
                        } label: {
                            if itemListConfiguration.modal {
                                Label {
                                    Text("Close", bundle: .module)
                                } icon: {
                                    Image(systemName: "xmark.circle")
                                }
                            } else {
                                Label {
                                    Text("Ok", bundle: .module)
                                } icon: {
                                    Image(systemName: "checkmark.circle")
                                }
                            }
                        }
                    }
                }
        }
        .applyIf(sizeMode == .small) { content in
            content
                .listStyle(.inset(alternatesRowBackgrounds: true))
        }
#endif
        .environment(\.defaultMinListHeaderHeight, 44)
#if os(iOS) || os(visionOS)
        .onAppear {
            guard listController.model.selectionMode != nil else { return }
            Task { @MainActor in
                try await Task.sleep(for: .seconds(0.5))
                guard selectedItems != Set(listController.model.selectedItems) else { return }
                withAnimation { selectedItems = Set(listController.model.selectedItems) }
            }
        }
#endif
        .onChange(of: selectedItems) {
#if os(iOS) || os(visionOS)
            if editMode?.wrappedValue == .active {
                listController.resetSelectedItem(selection: selectedItems, disableSelection: true)
                return
            }
#endif
            guard listController.model.selectionMode == nil else { return }
            let newSelectedItems = selectedItems
            Task { @MainActor in
                withAnimation { listController.resetSelectedItem(selection: newSelectedItems, disableSelection: !listController.model.allowEditing && childrenConfiguration.disableSelection) }
                if selectedItems != Set(listController.model.selectedItems) {
                    withAnimation { selectedItems = Set(listController.model.selectedItems) }
                }
            }
        }
        .onChange(of: listController.model.scrollItem, initial: true) {
            guard let newValue = listController.model.scrollItem else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                withAnimation { scrollProxy.scrollTo(newValue.id, anchor: .center) }
                listController.model.scrollItem = nil
            }
        }
        .onChange(of: listController.model.selectedItems) {
            if sizeMode == .small && listController.model.selectionMode != nil && !childrenConfiguration.canNavigate {
                return
            }
            let newSelection = Set(listController.model.selectedItems)
            Task { @MainActor in
                guard selectedItems != newSelection else { return }
                withAnimation { selectedItems = newSelection }
            }
        }
        .onKeyPress(characters: .alphanumerics, phases: .down) { keyPress in
            selectItem(matching: keyPress.characters)
        }
    }

#if os(macOS)
    func selectItem(_ direction: MoveCommandDirection) {
        withAnimation { listController.selectItem(directionUp: direction == .up) }
    }
#endif

    func selectItem(matching characters: String) -> KeyPress.Result {
        var result: Bool = false
        result = listController.selectItem(matching: characters)
        return result ? .handled : .ignored
    }
}
