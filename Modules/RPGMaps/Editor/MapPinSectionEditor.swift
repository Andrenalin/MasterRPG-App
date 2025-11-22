// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import PhotoRPG

struct MapPinSectionEditor: View {
    let editController: EditController
    
    @Environment(MapRootModel.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionModel
    
    @State private var showMapEditor = false
    @State private var showSelectorForId: UUID?
        
    var body: some View {
        @Bindable var model = editController.model
        
        PinSectionEditor(editControllable: editController) { pinId, showLink in
            editContent(pinId: pinId, showLink: showLink)
        } contentView: { pinId, showLink in
            HStack {
                Text(model[MapPinId.id, pinId].name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                PinImageDropArea(root: root, editController: editController, pin:  model[MapPinId.id, pinId])
            }
        } showLinkView: { linkValue in
            showLink(linkValue: linkValue)
        } swipeActionView: { pinId, showLink in
            swipeButtons(for: pinId, keypath: \.[pinId].content, showLink: showLink)
        } menuView: { pinId, selection, showLink in
            contextMenu(for: pinId, selection: selection, showLink: showLink, keypath: nil)
        } linkActionView: { pinId, showLink in
            actionBarView(selection: pinId, showLink: showLink)
        }
        .onChange(of: showSelectorForId) {
            guard let showSelectorForId else { return }
            selectionModel.selectionView = AnyView(showPhotoSelectionView(for: showSelectorForId))
            self.showSelectorForId = nil
            withAnimation { selectionModel.selection = true }
        }
        .onChange(of: showMapEditor) {
            guard showMapEditor else { return }
            selectionModel.selectionFullView = AnyView(mapEditView)
            selectionModel.idealSize = model.mapIdealSize
            showMapEditor = false
            withAnimation { selectionModel.selectionFullScreen = true }
        }
    }
    
    @ViewBuilder
    private func editContent(pinId: UUID, showLink: Binding<ShowLinkEntryAction<MapModel>?>) -> some View {
        @Bindable var model = editController.model
        Group {
            TextFieldEditor(editController: editController, model: $model[MapPinId.id, pinId].name, title: "Name", prompt: "Enter a name for the pin", bundle: .module)
            
            ToggleEditor(editController: editController, model: $model[MapPinId.id, pinId].isShown, title: "Shown", bundle: .module)
            
            ValuePickerEditor(editController: editController, model: $model[MapPinId.id, pinId].size, allCategories: MapPinModel.MapPinSize.allCases, title: "Size", bundle: .module) { size in
                Text(size.text)
            }
            
            root.photoRoot.viewController.inlinePhotoSelectionButton(root: root.photoRoot, editController: editController, photoId: $model[MapPinId.id, pinId].photoId, entryId: pinId, showSelector: $showSelectorForId)
                        
            UpdateMapPinEditor(editController: editController, entryId: nil, pinId: pinId)
            
            editEntryButtonView(entryId: pinId)
        }
    }
    
    @ViewBuilder
    private func showLink(linkValue: ShowLinkEntryAction<MapModel>) -> some View {
        editController.selectPhoto(for: linkValue.entryId) { selectionModel.selection = false }
    }
    
    @ViewBuilder
    private func swipeButtons(for entryId: UUID, keypath: WritableKeyPath<MapModel, String>, showLink: Binding<ShowLinkEntryAction<MapModel>?>) -> some View {
        LinkSelectionButton(entryId: entryId, type: .photo, keyPath: keypath, title: "Photo", bundle: .module, showLink: showLink)
    }
    
    @ViewBuilder
    private func contextMenu(for entryId: UUID?, selection: [UUID], showLink: Binding<ShowLinkEntryAction<MapModel>?>, keypath: WritableKeyPath<MapModel, String>?) -> some View {
        
        if let entryId {
            editEntryButtonView(entryId: entryId)
            
            if keypath != nil {
                Divider()
                
                LinkSelectionButton(entryId: entryId, type: .photo, keyPath: keypath, title: "Photo", bundle: .module, showLink: showLink)
            }
        }
    }
    
    @ViewBuilder
    private func actionBarView(selection: UUID?, showLink: Binding<ShowLinkEntryAction<MapModel>?>) -> some View {
        LinkWindowButton(type: .photo)
        LinkWindowButton(type: .value)
    }
    
    private func editEntryButtonView(entryId: MapEntryModel.ID) -> some View {
        Button {
            withAnimation {
                editController.editorModel.currentEntryId = entryId
                showMapEditor.toggle()
            }
        } label: {
            Label { Text("Edit Pin on Map", bundle: .module) } icon: { Image(systemName: "pencil") }
        }
    }
    
    private func showPhotoSelectionView(for selectedId: UUID) -> some View {
        root.photoRoot.viewController.viewSelect(root: root.photoRoot, filter: .character) {
            editController.selectedPinPhoto(for: selectedId)
        } toggleSelection: { selection, _ in
            editController.toggleSelectedPinPhoto(for: selectedId, selection: selection)
        } dismissAction: {
            selectionModel.selection = false
        }
    }
    
    private var mapEditView: some View {
        RootEditCanvasMap(editController: editController, isPinEdit: true)
            .environment(root)
#if os(iOS)
            .statusBar(hidden: true)
#endif
    }
}

#Preview {
    MapPinSectionEditor(editController: .preview)
        .environment(MapRootModel.previewWithData)
        .environment(ListModel.preview)
}

struct PinSectionEditor<EditContent: View, Content: View, ShowLink: View, SwipeAction: View, MenuContent: View, LinkAction: View>: View {
    init(editControllable: EditController, @ViewBuilder editContentView: @escaping (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> EditContent, @ViewBuilder contentView: @escaping (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> Content, @ViewBuilder showLinkView: @escaping (ShowLinkEntryAction<EditController.Model>) -> ShowLink, @ViewBuilder swipeActionView: @escaping (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> SwipeAction, @ViewBuilder menuView: @escaping (UUID?, [UUID], Binding<ShowLinkEntryAction<EditController.Model>?>) -> MenuContent, @ViewBuilder linkActionView: @escaping (UUID?, Binding<ShowLinkEntryAction<EditController.Model>?>) -> LinkAction) {
        self.editControllable = editControllable
        self.editContentView = editContentView
        self.contentView = contentView
        self.showLinkView = showLinkView
        self.swipeActionView = swipeActionView
        self.menuView = menuView
        self.linkActionView = linkActionView
    }
    
    let editControllable: EditController
    let editContentView: (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> EditContent
    let contentView: (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> Content
    let showLinkView: (ShowLinkEntryAction<EditController.Model>) -> ShowLink
    let swipeActionView: (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> SwipeAction
    let menuView: (UUID?, [UUID], Binding<ShowLinkEntryAction<EditController.Model>?>) -> MenuContent
    let linkActionView: (UUID?, Binding<ShowLinkEntryAction<EditController.Model>?>) -> LinkAction
    
    @Environment(\.colorScheme) private var colorScheme
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    
    @Environment(ListModel.self) private var itemListModel
    
    @State private var showLink: ShowLinkEntryAction<EditController.Model>?
    
    @State private var selection: UUID? = nil
    @State private var expandedEntries: [UUID: Bool] = [:]
    @State private var selectedEntries: [UUID] = []
    
    @State private var showDeleteAlert: Bool = false
    @State private var removeEntryList = RemoveEntryListModel()
    
    var body: some View {
        Section {
            ForEach(model.mapPins) { pin in
                DisclosureGroupTV(isExpanded: expandedEntry(entryId: pin.id)) {
                    editContentView(pin.id, $showLink)
                        .deleteDisabled(true)
                        .moveDisabled(true)
                        .listRowBackground(Rectangle().fill(colorRow))
#if !os(tvOS)
                        .listRowSeparatorTint(Color.accentColor)
#endif
                    
                } label: {
                    contentView(pin.id, $showLink)
#if os(iOS)
                        .selectListItem(isActive: editMode?.wrappedValue == .active ) {
                            if let index =  selectedEntries.firstIndex(of: pin.id) {
                                selectedEntries.remove(at: index)
                            } else {
                                selectedEntries.append(pin.id)
                            }
                        } isSelected: {
                            selectedEntries.contains(pin.id)
                        }
#endif
                        .contextMenu {
                            contextMenu(for: pin)
                        }
#if !os(tvOS)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            swipeButtons(for: pin.id)
                        }
#endif
                }
                .id(pin.id)
            }
            .onDelete(perform: removeSync(indexSet:))
            .onMove(perform: move(from:to:))
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            actionBarView
        } footer: {
            if !model.mapPins.isEmpty {
                actionBarView
            }
        }
#if os(macOS)
        .onDeleteCommand {
            guard let selection else { return }
            Task {
                checkDeleteEntries(ids: [selection], alwaysDeleteCheck: true)
            }
        }
#endif
        .onChange(of: editControllable.editorModel.currentItemId, initial: true) {
            guard editControllable.editorModel.currentItemId != nil else { return }
            withAnimation {
                expandedEntries = [:]
                selectedEntries = []
            }
        }
        .onChange(of: editControllable.editorModel.currentSecondaryId, initial: true) {
            guard let pinId = editControllable.editorModel.currentSecondaryId else { return }
            
            if expandedEntries[pinId, default: false] == false {
                withAnimation {
                    expandedEntries = [:]
                    expandedEntries[pinId] = true
                }
            }
        }
        .onChange(of: model.mapPins) {
            selectedEntries = selectedEntries.filter { pinId in
                model.mapPins.contains(where: { $0.id == pinId })
            }
        }
        .sheet(item: $showLink) { linkValue in
            showLinkView(linkValue)
                .itemListConfiguration(modalOk: true)
                .environment(\.colorScheme, colorScheme)
        }
        .sheetFullScreen(isPresented: $showDeleteAlert) {
            EffectedLinkAction(itemControllable: editControllable.itemControllable, removeEntryList: removeEntryList) {
                deleteSelectedEntries(rowModels: $0)
            }
        }
    }
    
    private func removeSync(indexSet: IndexSet) {
        remove(indexSet: indexSet)
    }
}

private extension PinSectionEditor {
    var colorRow: Color {
        colorScheme == .dark ? .white.opacity(0.2) : .black.opacity(0.2)
    }
    
    var model: EditController.Model {
        editControllable.model
    }
    
    func expandedEntry(entryId: UUID) -> Binding<Bool> {
        Binding {
            expandedEntries[entryId, default: false]
        } set: {
            expandedEntries[entryId] = $0
        }
    }
    
    func removeEntryState(for entryId: UUID) {
        expandedEntries[entryId] = nil
        if let index = selectedEntries.firstIndex(of: entryId) {
            selectedEntries.remove(at: index)
        }
    }
    
    func move(from: IndexSet, to: Array<UUID>.Index) {
        withAnimation { editControllable.move(pinFrom: from, to: to) }
    }
    
    @ViewBuilder
    func swipeButtons(for entryId: UUID) -> some View {
        swipeActionView(entryId, $showLink)
    }
    
    @ViewBuilder
    func contextMenu(for entry: MapPinModel) -> some View {
#if os(iOS)
        let entryId: UUID? = editMode?.wrappedValue == .active ? nil : entry.id
#else
        let entryId: UUID? = nil
#endif
        menuView(entryId, selectedEntries, $showLink)
        
        Divider()
        
        Button {
            withAnimation { editControllable.copy(pinId: entry.id) }
        } label: {
            Text("Copy row \(String(entry.name.prefix(16)))", bundle: .module)
        }
        
        Button(role: .destructive) {
            checkDeleteEntries(ids: [entry.id])
        } label: {
            Label { Text("Delete row \(String(entry.name.prefix(16)))", bundle: .module) } icon: { Image(systemName: "trash") }
                .foregroundStyle(.red)
        }
    }
    
    var actionBarView: some View {
        HStack {
            linkActionView(selection, $showLink)
            
            Spacer()
            
            Text("\(model.mapPins.count) Pin", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Spacer()
            
            Button {
                withAnimation {
                    expandedEntries = [:]
                    editControllable.editorModel.activateDetailEditMode.toggle()
                }
            } label: {
                Image(systemName: "square.and.pencil")
            }
            
            Button {
                withAnimation {
                    let entryId = editControllable.addNewPin()
                    expandedEntries = [entryId: true]
                    itemListModel.scrollEntryId = entryId
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

private extension PinSectionEditor {
    func checkDeleteEntries(ids: [UUID], alwaysDeleteCheck: Bool = false) {
        removeEntryList.removeItems = ids.map { ItemRowModel(itemId: model.id, entryId: $0, typeId: editControllable.itemControllable.itemDataModel.networkModule) }

        if alwaysDeleteCheck {
            showDeleteAlert.toggle()
        } else {
            if editControllable.isUsed(rowModels: removeEntryList.removeItems) {
                showDeleteAlert.toggle()
            } else {
                deleteSelectedEntries(rowModels: removeEntryList.removeItems)
            }
        }
    }
        
    func deleteSelectedEntries(rowModels: [ItemRowModel]) {
        for rowModel in rowModels {
            guard let entryId = rowModel.entryId else { continue }
            removeEntryState(for: entryId)
            editControllable.remove(pinIds: [entryId])
        }
    }
    
    func remove(indexSet: IndexSet) {
        let ids = indexSet.map { editControllable.model.mapPins[$0].id }
        removeEntryList.removeItems = ids.map { ItemRowModel(itemId: model.id, entryId: $0, typeId: editControllable.itemControllable.itemDataModel.networkModule) }

        deleteSelectedEntries(rowModels: removeEntryList.removeItems)
    }
}
