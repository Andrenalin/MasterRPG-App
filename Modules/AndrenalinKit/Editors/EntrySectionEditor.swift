// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class EntrySectionEditorModel<Model> {
    public init(showLink: ShowLinkEntryAction<Model>? = nil, selection: UUID? = nil, expandedEntries: [UUID : Bool] = [:], selectedEntries: [UUID] = [], showDeleteAlert: Bool = false, removeEntryList: RemoveEntryListModel = RemoveEntryListModel()) {
        self.showLink = showLink
        self.selection = selection
        self.expandedEntries = expandedEntries
        self.selectedEntries = selectedEntries
        self.showDeleteAlert = showDeleteAlert
        self.removeEntryList = removeEntryList
    }
    
    public var showLink: ShowLinkEntryAction<Model>?

    var selection: UUID?
    var expandedEntries: [UUID: Bool]
    public var selectedEntries: [UUID]

    var showDeleteAlert: Bool
    var removeEntryList: RemoveEntryListModel
}

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

    public init(
        editControllable: EditController,
        entrySectionEditorModel: EntrySectionEditorModel<EditController.Model>,
        @ViewBuilder editContentView: @escaping (UUID) -> EditContent,
        @ViewBuilder contentView: @escaping (UUID) -> Content,
        @ViewBuilder showLinkView: () -> ShowLink,
        @ViewBuilder swipeActionView: @escaping (UUID) -> SwipeAction,
        @ViewBuilder menuView: @escaping (UUID?) -> MenuContent,
        @ViewBuilder linkActionView: () -> LinkAction,
        @ViewBuilder addActionView: () -> AddAction = EmptyView.init
    ) {
        self.editControllable = editControllable
        self.entrySectionEditorModel = entrySectionEditorModel
        self.editContentView = editContentView
        self.contentView = contentView
        self.showLinkView = showLinkView()
        self.swipeActionView = swipeActionView
        self.menuView = menuView
        self.linkActionView = linkActionView()
        self.addActionView = addActionView()
    }

    let editControllable: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<EditController.Model>
    let editContentView: (UUID) -> EditContent
    let contentView: (UUID) -> Content
    let showLinkView: ShowLink
    let swipeActionView: (UUID) -> SwipeAction
    let menuView: (UUID?) -> MenuContent
    let linkActionView: LinkAction
    let addActionView: AddAction

    @Environment(\.colorScheme) private var colorScheme
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif

    @Environment(ListModel.self) private var itemListModel
    @Environment(SelectionSheetLinkModel.self) private var selectionModel

    public var body: some View {
        let _ = Self._printChanges()
        Section {
            ForEach(editControllable.editEntries) { entry in
                DisclosureGroupTV(isExpanded: expandedEntry(entryId: entry.id)) {
                    editContentView(entry.id)
                        .deleteDisabled(true)
                        .moveDisabled(true)
                        .listRowBackground(Rectangle().fill(colorRow))
#if !os(tvOS)
                        .listRowSeparatorTint(Color.accentColor)
#endif

                } label: {
                    contentView(entry.id)
#if os(iOS)
                        .selectListItem(isActive: editMode?.wrappedValue == .active ) {
                            if let index = entrySectionEditorModel.selectedEntries.firstIndex(of: entry.id) {
                                entrySectionEditorModel.selectedEntries.remove(at: index)
                            } else {
                                entrySectionEditorModel.selectedEntries.append(entry.id)
                            }
                        } isSelected: {
                            entrySectionEditorModel.selectedEntries.contains(entry.id)
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
            .onDelete(perform: remove(indexSet:))
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
            guard let selection = entrySectionEditorModel.selection else { return }
            checkDeleteEntries(ids: [selection], alwaysDeleteCheck: true)
        }
#endif
        .onChange(of: editControllable.editorModel.currentItemId, initial: true) {
            guard editControllable.editorModel.currentItemId != nil else { return }
            withAnimation {
                entrySectionEditorModel.expandedEntries = [:]
                entrySectionEditorModel.selectedEntries = []
            }
        }
        .onChange(of: editControllable.editorModel.currentEntryId, initial: true) {
            guard let entryId = editControllable.editorModel.currentEntryId else { return }

            if entrySectionEditorModel.expandedEntries[entryId, default: false] == false {
                withAnimation {
                    entrySectionEditorModel.expandedEntries = [:]
                    entrySectionEditorModel.expandedEntries[entryId] = true
                }
            }
        }
        .onChange(of: model.entries) {
            entrySectionEditorModel.selectedEntries = entrySectionEditorModel.selectedEntries.filter { entryId in
                model.entries.contains(where: { $0.id == entryId })
            }
        }
        .onChange(of: entrySectionEditorModel.showLink?.id) {
            guard entrySectionEditorModel.showLink != nil else { return }
            selectionModel.selectionView = AnyView(showLinkView)
            entrySectionEditorModel.showLink = nil
            withAnimation { selectionModel.selection = true }
        }
        .onChange(of: entrySectionEditorModel.showDeleteAlert) {
            guard entrySectionEditorModel.showDeleteAlert else { return }
            selectionModel.selectionFullView = AnyView(effectedLinkView)
            selectionModel.idealSize = CGSize(width: 600, height: 800)
            entrySectionEditorModel.showDeleteAlert = false
            withAnimation { selectionModel.selectionFullScreen = true }
        }
    }
    
    private var effectedLinkView: some View {
        EffectedLinkAction(itemControllable: editControllable.itemControllable, removeEntryList: entrySectionEditorModel.removeEntryList) {
            deleteSelectedEntries(rowModels: $0)
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
            entrySectionEditorModel.expandedEntries[entryId, default: false]
        } set: {
            entrySectionEditorModel.expandedEntries[entryId] = $0
        }
    }

    func removeEntryState(for entryId: UUID) {
        entrySectionEditorModel.expandedEntries[entryId] = nil
        if let index = entrySectionEditorModel.selectedEntries.firstIndex(of: entryId) {
            entrySectionEditorModel.selectedEntries.remove(at: index)
        }
    }

    func move(from: IndexSet, to: Array<UUID>.Index) {
        editControllable.move(entryFrom: from, to: to)
    }

    @ViewBuilder
    func swipeButtons(for entryId: UUID) -> some View {
        swipeActionView(entryId)
    }

    @ViewBuilder
    func contextMenu(for entry: EditController.Model.Entry) -> some View {
#if os(iOS)
        let entryId: UUID? = editMode?.wrappedValue == .active ? nil : entry.id
#else
        let entryId: UUID? = nil
#endif
        menuView(entryId)

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
                linkActionView

                Spacer()
                
                actionTitleAddBarView
            }

            VStack {
                HStack {
                    linkActionView
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
                    entrySectionEditorModel.expandedEntries = [:]
                    editControllable.editorModel.activateDetailEditMode.toggle()
                }
            } label: {
                Image(systemName: "square.and.pencil")
            }
            
            addActionView
            
            Button {
                let entryId = editControllable.addNewEntry()
                withAnimation {
                    entrySectionEditorModel.expandedEntries = [entryId: true]
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
        entrySectionEditorModel.removeEntryList.removeItems = ids.map { ItemRowModel(itemId: model.id, entryId: $0, typeId: editControllable.itemControllable.itemDataModel.networkModule) }
        if alwaysDeleteCheck {
            withAnimation { entrySectionEditorModel.showDeleteAlert.toggle() }
        } else {
            if editControllable.isUsed(rowModels: entrySectionEditorModel.removeEntryList.removeItems) {
                withAnimation { entrySectionEditorModel.showDeleteAlert.toggle() }
            } else {
                deleteSelectedEntries(rowModels: entrySectionEditorModel.removeEntryList.removeItems)
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

    func remove(indexSet: IndexSet) {
        let ids = indexSet.map { editControllable.model.entries[$0].id }
        entrySectionEditorModel.removeEntryList.removeItems = ids.map { ItemRowModel(itemId: model.id, entryId: $0, typeId: editControllable.itemControllable.itemDataModel.networkModule) }

        if editControllable.isUsed(rowModels: entrySectionEditorModel.removeEntryList.removeItems) {
            let copyEntries = model.entries
            deleteSelectedEntries(rowModels: entrySectionEditorModel.removeEntryList.removeItems)
            editControllable.model.entries = copyEntries
            checkDeleteEntries(ids: ids, alwaysDeleteCheck: true)
        } else {
            deleteSelectedEntries(rowModels: entrySectionEditorModel.removeEntryList.removeItems)
        }
    }
}
