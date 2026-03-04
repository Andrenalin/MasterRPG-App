// @copyright André Trettin

import SwiftUI

struct SheetEntryView<LinkType: LinkDataTransferable>: View {
    init(root: ItemRootController, model: TableSheetModel, entry: SheetModel, isEditor: Bool, linkTypes: LinkType.Type) {
        self.root = root
        self.model = model
        self.entry = entry
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }
    
    let root: ItemRootController
    let model: TableSheetModel
    let entry: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    
    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame
    @Environment(\.gameModus) private var gameModus
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(entry.inlineEntries) { inlineSheet in
                switch inlineSheet.sheetType {
                case .photoInline:
                    root.viewControllable.rowViewer(source: entry.source, destination: entry.destination)
                        .frame(height: 96)
                        .frame(maxWidth: .infinity, alignment: .center)
                default:
                    EmptyView()
                }
            }

            HStack {
                if (isEditor || entry.editType != .none) && (entry.sheetType == .item || entry.sheetType == .group) {
                    editButton(onlyIcon: true)
                }
                
                switch entry.sheetType {
                case .item, .group:
                    LinkHighlightTextView(model: model.linkTextModel(for: .entry(entry.id), text: text, shareResults: shareResult))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.body)
                        .listRowBackground(rowColor(for: entry.level))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8 + CGFloat(entry.level * 4), bottom: 8, trailing: 8))
                    
                case .dice:
                    root.viewControllable.rowViewer(source: entry.source, destination: entry.destination)
                case .pdf, .photo, .space, .weather:
                    root.viewControllable.rowViewer(source: entry.source, destination: entry.destination)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .frame(height: 256)
                case .audioInline:
                    HStack {
                        root.viewControllable.rowViewer(source: entry.source, destination: entry.destination)
                        LinkHighlightTextView(model: model.linkTextModel(for: .entry(entry.id), text: text, shareResults: shareResult))
                    }
                    .font(.body)
                    .listRowBackground(rowColor(for: entry.level))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8 + CGFloat(entry.level * 4), bottom: 8, trailing: 8))
                case .photoInline, .edit:
                    EmptyView()
                }
                                
                if (isEditor) && (entry.sheetType == .item || entry.sheetType == .group) {
                    deleteButton(onlyIcon: true)
                }
            }
            
            ForEach(entry.inlineEntries) { inlineSheet in
                switch inlineSheet.sheetType {
                case .dice:
                    root.viewControllable.rowViewer(source: inlineSheet.source, destination: entry.destination)
                case .pdf:
                    root.viewControllable.rowViewer(source: inlineSheet.source, destination: entry.destination)
                default:
                    EmptyView()
                }
            }
        }
        .contentShape(.rect)
        .moveDisabled(entry.sheetType != .item && entry.sheetType != .group)
#if !os(tvOS)
        .applyIf(isEditor && entry.sheetType == .item) {
            $0.dropDestination(for: linkTypes, isEnabled: entry.sheetType != .group) { items, sessions in
                guard let editController = root.editControllable as? (any EntryDataEditable), let entryId = entry.source.entryId else { return }
                items.forEach {
                    editController.add(link: $0.name, module: $0.module, itemId: $0.itemId, entryId: $0.entryId, destinationItemId: entry.source.itemId, destinationEntryId: entryId)
                    withAnimation {
                        model.update(entryId: entryId)
                        model.updateParent()
                    }
                }
            }
            .contextMenu {
                editButton(onlyIcon: false)
                Divider()
                if let entryEditable {
                    moveIntoButton(entryEditable: entryEditable, groups: model.groupFolders(entryDataEditable: entryEditable, entry: entry))
                }
                moveUpButton
                moveDownButton
                Divider()
                duplicateButton
#if os(iOS)
                linkButton
#endif
                Divider()
                deleteButton(onlyIcon: false)
            }
        }
#endif
        
        
        ForEach(entry.sheetIds, id: \.self) { sheetId in
            if let sheetModel = model.sheets[sheetId] {
                SheetView(root: root, model: sheetModel, isEditor: isEditor, linkTypes: linkTypes)
            }
        }
    }
}

private extension SheetEntryView {
    var entryEditable: (any EntryDataEditable)? {
        root.editControllable as? (any EntryDataEditable)
    }
    
    func editButton(onlyIcon: Bool) -> some View {
        Button {
            withAnimation {
                if isEditor {
                    root.editControllable.setCurrentItem(to: ItemRowTreeModel(itemId: entry.source.itemId, entryId: entry.source.entryId, typeId: entry.source.typeId))
                } else {
                    model.toggleEdit(entry: entry)
                }
            }
        } label: {
            Label {
                Text("Edit \(entry.name.withoutLink())", bundle: .module)
            } icon: {
                Image(systemName: "square.and.pencil")
                    .opacity(0)
                    .imageScale(.large)
                    .overlay {
                        Image(systemName: model.isEditing(entry: entry) ? "square.and.pencil" : "pencil")
                            .imageScale(.large)
                            .foregroundStyle(.tint, .foreground, .tint)
                            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                    }
            }
            .applyIf(onlyIcon) {
                $0.labelStyle(.iconOnly)
            }
        }
        .borderLessTVBottonStyle()
#if !os(tvOS)
        .keyboardShortcut("e", modifiers: .shift)
#endif
    }
    
    var duplicateButton: some View {
        Button {
            guard let entryId = entry.source.entryId, let newId = entryEditable?.copy(itemId: entry.source.itemId, entryId: entryId) else { return }
            
            withAnimation {
                model.add(entryId: newId)
                root.editControllable.setCurrentItem(to: ItemRowTreeModel(itemId: entry.source.itemId, entryId: newId, typeId: entry.source.typeId))
                model.updateParent()
            }
        } label: {
            Label {
                Text("Duplicate \(entry.name.withoutLink())", bundle: .module)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("d", modifiers: .shift)
#endif
    }
    
    var linkButton: some View {
        Button {
            guard let entryEditable, let entryId = entry.source.entryId else { return }
            navigator.navigate(to: entryEditable.linkSelectionDestination(itemRowModel: ItemRowModel(itemId: entry.source.itemId, entryId: entryId, typeId: entry.source.typeId)), method: .managedSheet)
        } label: {
            Label {
                Text("Add Links", bundle: .module)
            } icon: {
                Image(systemName: "link.badge.plus")
            }
        }
    }

    @ViewBuilder
    func moveIntoButton(entryEditable: any EntryDataEditable, groups: [FolderRepresentable]) -> some View {
        if !groups.isEmpty {
            Menu {
                ForEach(groups) { folder in
                    Button {
                        model.move(entryDataEditable: entryEditable, entry: entry, into: folder)
                    } label: {
                        Label {
                            Text(folder.name)
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                }
            } label: {
                Label {
                    Text("Move \(entry.name.withoutLink()) into", bundle: .module)
                } icon: {
                    Image(systemName: "list.bullet.indent")
                }
            }
        }
    }

    var moveUpButton: some View {
        Button {
            guard let currentIndex = model.sheetModel.entries.firstIndex(where: { $0.id == entry.id }), currentIndex > 0 else { return }
            withAnimation {
                model.move(entryDataEditable: entryEditable, indexSet: IndexSet(integer: currentIndex), to: currentIndex - 1)
            }
        } label: {
            Label {
                Text("Move Up", bundle: .module)
            } icon: {
                Image(systemName: "arrow.up")
            }
        }
        .disabled(model.sheetModel.entries.first?.id == entry.id)
#if !os(tvOS)
        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
#endif
    }

    var moveDownButton: some View {
        Button {
            guard let currentIndex = model.sheetModel.entries.firstIndex(where: { $0.id == entry.id }), currentIndex < model.sheetModel.entries.count - 1 else { return }
            withAnimation {
                model.move(entryDataEditable: entryEditable, indexSet: IndexSet(integer: currentIndex), to: currentIndex + 2)
            }
        } label: {
            Label {
                Text("Move Down", bundle: .module)
            } icon: {
                Image(systemName: "arrow.down")
            }
        }
        .disabled(model.sheetModel.entries.last?.id == entry.id)
#if !os(tvOS)
        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
#endif
    }
    
    func deleteButton(onlyIcon: Bool) -> some View {
        Button(role: .destructive) {
            withAnimation {
                root.editControllable.removeEntry(source: entry.source)
                model.remove(entry: entry)
                model.updateParent()
            }
        } label: {
            Label {
                Text("Delete \(entry.name.withoutLink())", bundle: .module)
            } icon: {
                Image(systemName: "minus.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.white, .red, .red)
            }
            .applyIf(onlyIcon) {
                $0.labelStyle(.iconOnly)
            }
        }
        .borderLessTVBottonStyle()
#if !os(tvOS)
        .keyboardShortcut("r", modifiers: .shift)
#endif
    }
    
    func rowColor(for level: Int) -> Color {
#if os(macOS) || os(visionOS)
        .clear
#else
        level.isMultiple(of: 2) ? (colorScheme == .dark ? .black : .white) : .secondary.opacity(0.3)
#endif
    }
    
    var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: entry.source.itemId, childId: entry.source.entryId, module: entry.source.typeId), showGame: showGame, gameModus: gameModus)
    }
    
    var text: String {
        if entry.description.isEmpty {
            entry.name
        } else if entry.name.isEmpty {
            entry.description
        } else {
            "**" + entry.name + "**: " + entry.description
        }
    }
}
