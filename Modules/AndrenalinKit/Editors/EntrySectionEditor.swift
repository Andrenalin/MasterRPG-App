// @copyright André Trettin

import SwiftUI

public struct ShowLinkEntryAction<Model>: Identifiable {
    public init(id: UUID, entryId: UUID, type: NetworkModules, keyPath: WritableKeyPath<Model, String>?) {
        self.id = id
        self.entryId = entryId
        self.type = type
        self.keyPath = keyPath
    }

    public let id: UUID
    public let entryId: UUID
    public let type: NetworkModules
    public let keyPath: WritableKeyPath<Model, String>?
}

public struct EntrySectionEditor<EditController: EntryDataEditable, EditContent: View, Content: View, ShowLink: View, SwipeAction: View, MenuContent: View, LinkAction: View, AddAction: View>: View {
    public init(editControllable: EditController, @ViewBuilder editContentView: @escaping (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> EditContent, @ViewBuilder contentView: @escaping (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> Content, @ViewBuilder showLinkView: @escaping (ShowLinkEntryAction<EditController.Model>) -> ShowLink, @ViewBuilder swipeActionView: @escaping (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> SwipeAction, @ViewBuilder menuView: @escaping (UUID?, [UUID], Binding<ShowLinkEntryAction<EditController.Model>?>) -> MenuContent, @ViewBuilder linkActionView: @escaping (UUID?, Binding<ShowLinkEntryAction<EditController.Model>?>) -> LinkAction, @ViewBuilder addActionView: @escaping (Binding<ShowLinkEntryAction<EditController.Model>?>) -> AddAction) {
        self.editControllable = editControllable
        self.editContentView = editContentView
        self.contentView = contentView
        self.showLinkView = showLinkView
        self.swipeActionView = swipeActionView
        self.menuView = menuView
        self.linkActionView = linkActionView
        self.addActionView = addActionView
    }

    public init(editControllable: EditController, @ViewBuilder editContentView: @escaping (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> EditContent, @ViewBuilder contentView: @escaping (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> Content, @ViewBuilder showLinkView: @escaping (ShowLinkEntryAction<EditController.Model>) -> ShowLink, @ViewBuilder swipeActionView: @escaping (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> SwipeAction, @ViewBuilder menuView: @escaping (UUID?, [UUID], Binding<ShowLinkEntryAction<EditController.Model>?>) -> MenuContent, @ViewBuilder linkActionView: @escaping (UUID?, Binding<ShowLinkEntryAction<EditController.Model>?>) -> LinkAction) where AddAction == EmptyView {
        self.editControllable = editControllable
        self.editContentView = editContentView
        self.contentView = contentView
        self.showLinkView = showLinkView
        self.swipeActionView = swipeActionView
        self.menuView = menuView
        self.linkActionView = linkActionView
        self.addActionView = { _ in EmptyView() }
    }
    let editControllable: EditController
    let editContentView: (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> EditContent
    let contentView: (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> Content
    let showLinkView: (ShowLinkEntryAction<EditController.Model>) -> ShowLink
    let swipeActionView: (UUID, Binding<ShowLinkEntryAction<EditController.Model>?>) -> SwipeAction
    let menuView: (UUID?, [UUID], Binding<ShowLinkEntryAction<EditController.Model>?>) -> MenuContent
    let linkActionView: (UUID?, Binding<ShowLinkEntryAction<EditController.Model>?>) -> LinkAction
    let addActionView: (Binding<ShowLinkEntryAction<EditController.Model>?>) -> AddAction

    @Environment(\.colorScheme) private var colorScheme
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif

    @Environment(ListModel.self) private var itemListModel
    @Environment(SelectionSheetLinkModel.self) private var selectionModel

    @State private var showLink: ShowLinkEntryAction<EditController.Model>?

    @State private var selection: UUID? = nil
    @State private var expandedEntries: [UUID: Bool] = [:]
    @State private var selectedEntries: [UUID] = []

    @State private var showDeleteAlert: Bool = false
    @State private var removeEntryList = RemoveEntryListModel()
    
    public var body: some View {
        Section {
            ForEach(editControllable.editEntries) { entry in
                DisclosureGroupTV(isExpanded: expandedEntry(entryId: entry.id)) {
                    editContentView(entry.id, $showLink)
                        .deleteDisabled(true)
                        .moveDisabled(true)
                        .listRowBackground(Rectangle().fill(colorRow))
#if !os(tvOS)
                        .listRowSeparatorTint(Color.accentColor)
#endif

                } label: {
                    contentView(entry.id, $showLink)
#if os(iOS)
                        .selectListItem(isActive: editMode?.wrappedValue == .active ) {
                            if let index =  selectedEntries.firstIndex(of: entry.id) {
                                selectedEntries.remove(at: index)
                            } else {
                                selectedEntries.append(entry.id)
                            }
                        } isSelected: {
                            selectedEntries.contains(entry.id)
                        }
#endif
                        .contextMenu {
                            contextMenu(for: entry)
                        }
#if !os(tvOS)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            swipeButtons(for: entry.id)
                        }
#endif
                }
                .id(entry.id)
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
            if !model.entries.isEmpty {
                actionBarView
            }
        }
#if os(macOS)
        .onDeleteCommand {
            guard let selection else { return }
            checkDeleteEntries(ids: [selection], alwaysDeleteCheck: true)
        }
#endif
        .onChange(of: editControllable.editorModel.currentItemId, initial: true) {
            guard editControllable.editorModel.currentItemId != nil else { return }
            withAnimation {
                expandedEntries = [:]
                selectedEntries = []
            }
        }
        .onChange(of: editControllable.editorModel.currentEntryId, initial: true) {
            guard let entryId = editControllable.editorModel.currentEntryId else { return }

            if expandedEntries[entryId, default: false] == false {
                withAnimation {
                    expandedEntries = [:]
                    expandedEntries[entryId] = true
                }
            }
        }
        .onChange(of: model.entries) {
            selectedEntries = selectedEntries.filter { entryId in
                model.entries.contains(where: { $0.id == entryId })
            }
        }
        .onChange(of: showLinkToggle.wrappedValue) {
            guard let showLink else { return }
            selectionModel.selectionView = AnyView(showLinkView(showLink))
            self.showLink = nil
            withAnimation { selectionModel.selection = true }
        }
        .onChange(of: showDeleteAlert) {
            guard showDeleteAlert else { return }
            selectionModel.selectionFullView = AnyView(effectedLinkView)
            selectionModel.idealSize = CGSize(width: 600, height: 800)
            showDeleteAlert = false
            withAnimation { selectionModel.selectionFullScreen = true }
        }
    }
    
    private func removeSync(indexSet: IndexSet) {
        Task {
            await remove(indexSet: indexSet)
        }
    }

    private var effectedLinkView: some View {
        EffectedLinkAction(itemControllable: editControllable.itemControllable, removeEntryList: removeEntryList) {
            deleteSelectedEntries(rowModels: $0)
        }
    }
    
    var showLinkToggle: Binding<Bool> {
        Binding {
            showLink != nil
        } set: {
            if !$0 {
                showLink = nil
            }
        }
    }
}

private extension EntrySectionEditor {
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
        editControllable.move(entryFrom: from, to: to)
    }

    @ViewBuilder
    func swipeButtons(for entryId: UUID) -> some View {
        swipeActionView(entryId, $showLink)
    }

    @ViewBuilder
    func contextMenu(for entry: EditController.Model.Entry) -> some View {
#if os(iOS)
        let entryId: UUID? = editMode?.wrappedValue == .active ? nil : entry.id
#else
        let entryId: UUID? = nil
#endif
        menuView(entryId, selectedEntries, $showLink)

        Divider()

        Button {
            editControllable.copy(entryId: entry.id, shouldSave: true)
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
        ViewThatFits {
            HStack {
                linkActionView(selection, $showLink)
                
                Spacer()
                
                actionTitleAddBarView
            }

            VStack {
                HStack {
                    linkActionView(selection, $showLink)
                }
                
                actionTitleAddBarView
            }
        }
    }
    
    var actionTitleAddBarView: some View {
        HStack {
            Text("\(editControllable.editEntries.count) Entry", bundle: .module)
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
            
            addActionView($showLink)
            
            Button {
                let entryId = editControllable.addNewEntry()
                withAnimation {
                    expandedEntries = [entryId: true]
                    itemListModel.scrollEntryId = entryId
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

private extension EntrySectionEditor {
    func checkDeleteEntries(ids: [UUID], alwaysDeleteCheck: Bool = false) {
        removeEntryList.removeItems = ids.map { ItemRowModel(itemId: model.id, entryId: $0, typeId: editControllable.itemControllable.itemDataModel.networkModule) }
        if alwaysDeleteCheck {
            withAnimation { showDeleteAlert.toggle() }
        } else {
            if editControllable.isUsed(rowModels: removeEntryList.removeItems) {
                withAnimation { showDeleteAlert.toggle() }
            } else {
                deleteSelectedEntries(rowModels: removeEntryList.removeItems)
            }
        }
    }

    func deleteSelectedEntries(rowModels: [ItemRowModel]) {
        for rowModel in rowModels {
            guard let entryId = rowModel.entryId else { continue }
            removeEntryState(for: entryId)
            editControllable.remove(entryId: entryId)
        }
    }

    func remove(indexSet: IndexSet) async {
        let ids = indexSet.map { editControllable.model.entries[$0].id }
        removeEntryList.removeItems = ids.map { ItemRowModel(itemId: model.id, entryId: $0, typeId: editControllable.itemControllable.itemDataModel.networkModule) }
        
        if editControllable.isUsed(rowModels: removeEntryList.removeItems) {
            let copyEntries = model.entries
            deleteSelectedEntries(rowModels: removeEntryList.removeItems)
            editControllable.model.entries = copyEntries
            checkDeleteEntries(ids: ids, alwaysDeleteCheck: true)
        } else {
            deleteSelectedEntries(rowModels: removeEntryList.removeItems)
        }
    }
}
