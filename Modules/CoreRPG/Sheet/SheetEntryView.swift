// @copyright André Trettin

import SwiftUI

struct SheetEntryView<LinkType: LinkDataTransferable>: View {
    init(model: TableFirstSheetModel, entry: SheetFirstModel, isEditor: Bool, linkTypes: LinkType.Type) {
        self.model = model
        self.entry = entry
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }

    let model: TableFirstSheetModel
    let entry: SheetFirstModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator

    @State private var viewControllable: (any ViewControllable)?

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(entry.inlineEntries) { inlineSheet in
                switch inlineSheet.sheetType {
                case .photoInline:
                    viewControllable?.rowViewer(source: entry.source, destination: entry.destination)
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
                    viewControllable?.rowViewer(source: entry.source, destination: entry.destination)
                case .pdf, .photo, .space, .weather:
                    viewControllable?.rowViewer(source: entry.source, destination: entry.destination)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .frame(height: 256)
                case .audioInline:
                    HStack {
                        viewControllable?.rowViewer(source: entry.source, destination: entry.destination)
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
                    viewControllable?.rowViewer(source: inlineSheet.source, destination: entry.destination)
                case .pdf:
                    viewControllable?.rowViewer(source: inlineSheet.source, destination: entry.destination)
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
                guard let entryId = entry.source.entryId else { return }
                items.forEach {
                    model.addLink(link: $0.name, module: $0.module, itemId: $0.itemId, entryId: $0.entryId, to: entry.source)
                    withAnimation {
                        model.update(entryId: entryId)
                        model.updateParent()
                    }
                }
            }
        }
#endif
        .contextMenuAll {
            editButton(onlyIcon: false)
            if let entryEditable = model.entryDataEditable(for: entry.source) {
                SheetContextMenuView(entryEditable: entryEditable, model: model, entry: entry)
            }
            deleteButton(onlyIcon: false)
        }
        .task(id: entry.destination) {
            viewControllable = model.viewControllable(for: entry.destination)
        }


        ForEach(entry.sheetIds, id: \.self) { sheetId in
            if let sheetModel = model.sheets[sheetId], let root = model.rootController(for: sheetId.typeId) {
                SheetView(root: root, model: sheetModel, isEditor: isEditor, linkTypes: linkTypes)
            }
        }
    }
}

private extension SheetEntryView {
    func editButton(onlyIcon: Bool) -> some View {
        Button {
            withAnimation {
                if isEditor {
                    model.setCurrentItem(source: entry.source, entryId: entry.source.entryId)
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
        .keyboardShortcutAll("e", modifiers: .shift)
    }
    
    func deleteButton(onlyIcon: Bool) -> some View {
        Button(role: .destructive) {
            withAnimation {
                model.removeEntry(source: entry.source)
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
        .keyboardShortcutAll("r", modifiers: .shift)
    }
    
    func rowColor(for level: Int) -> Color {
#if os(macOS) || os(visionOS)
        .clear
#else
        level.isMultiple(of: 2) ? (colorScheme == .dark ? .black : .white) : .secondary.opacity(0.3)
#endif
    }
    
    var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: entry.source.itemId, childId: entry.source.entryId, module: entry.source.typeId), showGame: appGameStateModel.isGameRunning, gameModus: appGameStateModel.gameModus)
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
