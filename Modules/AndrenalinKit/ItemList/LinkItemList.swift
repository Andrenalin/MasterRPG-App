// @copyright André Trettin

import SwiftUI

public struct LinkItemList<Row: View>: View {
    public init(listController: any ListControllable, @ViewBuilder row: @escaping (ItemRowTreeModel, Bool) -> Row) {
        self.listController = listController
        self.rowView = row
        self._selectedItems = State(wrappedValue: Set(listController.model.selectedItems))
    }
    
    let listController: any ListControllable
    let rowView: (ItemRowTreeModel, Bool) -> Row
    
    @State private var selectedItems: Set<ItemRowTreeModel>

#if os(iOS) || os(visionOS)
    @State private var editMode: EditMode = .inactive
#endif
    
    public var body: some View {
        @Bindable var itemListModel = listController.model
        ScrollViewReader { scrollProxy in
            listView(scrollProxy: scrollProxy)
#if !os(tvOS)
                .contextMenu(forSelectionType: ItemRowTreeModel.self) { selection in
                    ItemListContextMenu(listController: listController, selection: selection, exportDisabled: false, generatorDisabled: true, removeEntryList: nil, showEditGroup: .constant(false), showExport: .constant(false))
                }
#endif
                .modifier(ItemListSearchableViewModifer(listController: listController))
#if os(iOS) || os(visionOS)
                .toolbar {
                    if itemListModel.selectionMode == nil {
                        ToolbarItem(id: "Edit\(itemListModel.listTitleName)", placement: .navigation) {
                            selectModeView
                        }
                    }
                }
                .toolbarRole(.automatic)
#endif
            
#if os(iOS) || os(visionOS)
                .environment(\.editMode, $editMode)
#endif
#if os(iOS) || os(visionOS)
                .toolbar( .visible, for: .navigationBar)
#elseif os(macOS)
                .toolbar(.visible, for: .automatic)
#endif
        }
    }
    
    @MainActor
    private func listView(scrollProxy: ScrollViewProxy) -> some View {
        List(selection: $selectedItems) {
            ItemListSection(listController: listController, rowView: rowView)
        }
        .animation(nil, value: listController.model.allowEditing)
        .scrollIndicatorsFlash(onAppear: true)
        .scrollIndicatorsFlash(trigger: listController.model.filteredItems.count)
#if !os(visionOS)
        .scrollDismissesKeyboard(.immediately)
#endif
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 300)
#endif
        .navigationTitle(listController.model.listTitleName)
#if os(iOS) || os(visionOS)
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.large)
#endif
#if os(macOS)
        .listStyle(.inset(alternatesRowBackgrounds: true))
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
            if editMode == .active {
                listController.resetSelectedItem(selection: selectedItems, disableSelection: true)
                return
            }
#endif
            guard listController.model.selectionMode == nil else { return }
            let newSelectedItems = selectedItems
            Task { @MainActor in
                withAnimation { listController.resetSelectedItem(selection: newSelectedItems, disableSelection: false) }
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
            if listController.model.selectionMode != nil {
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
    
#if os(iOS) || os(visionOS)
    @ViewBuilder
    var selectModeView: some View {
        Button {
            withAnimation {
                listController.model.selectedItems = []
                listController.model.allowEditing.toggle()
            }
        } label: {
            if listController.model.allowEditing {
                Text("Done", bundle: .module)
            } else {
                Text("Edit", bundle: .module)
            }
        }
    }
#endif

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
