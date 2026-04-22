// @copyright André Trettin

import SwiftUI

struct SheetEntryView<LinkType: LinkDataTransferable>: View {
    init(rootModel: SheetRootModel, entryModel: SheetModel, isEditor: Bool, linkTypes: LinkType.Type) {
        self.rootModel = rootModel
        self.entryModel = entryModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }

    let rootModel: SheetRootModel
    let entryModel: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator

    var body: some View {
        VStack(alignment: .leading) {
            beforeInline
            
            mainRow
            
            afterInline
        }
        .contentShape(.rect)
        .moveDisabled(entryModel.sheetType != .item && entryModel.sheetType != .group)
        
        ForEach(entryModel.entries) { subEntry in
            if let root = rootModel.rootController(for: subEntry.source.typeId), subEntry.isShown {
                SheetView(root: root, rootModel: rootModel, sheetModel: subEntry, isEditor: isEditor, linkTypes: linkTypes)
            }
        }
    }
}

private extension SheetEntryView {
    func viewController(for source: ItemRowModel) -> ViewControllable? {
        rootModel.linkControllable.rootManager.rootModel(for: source.typeId)?.viewControllable
    }
    
    var beforeInline: some View {
        ForEach(entryModel.inlineEntries) { inlineSheet in
            switch inlineSheet.sheetType {
            case .photoInline:
                viewController(for: entryModel.source)?.rowViewer(source: entryModel.source, destination: entryModel.destination)
                    .frame(height: 96)
                    .frame(maxWidth: .infinity, alignment: .center)
            default:
                EmptyView()
            }
        }
    }
    
    var mainRow: some View {
        HStack {
            if (isEditor || entryModel.editType != .none) && (entryModel.sheetType == .item || entryModel.sheetType == .group) {
                editButton(onlyIcon: true)
            }
            
            switch entryModel.sheetType {
            case .item, .group:
                LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(entryModel.id), text: text, shareResults: shareResult))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.body)
                    .listRowBackground(rowColor(for: entryModel.level))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8 + CGFloat(entryModel.level * 4), bottom: 8, trailing: 8))
                
            case .dice:
                viewController(for: entryModel.source)?.rowViewer(source: entryModel.source, destination: entryModel.destination)
            case .pdf, .photo, .space, .weather:
                viewController(for: entryModel.source)?.rowViewer(source: entryModel.source, destination: entryModel.destination)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .frame(height: 256)
            case .audioInline:
                HStack {
                    viewController(for: entryModel.source)?.rowViewer(source: entryModel.source, destination: entryModel.destination)
                    LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(entryModel.id), text: text, shareResults: shareResult))
                }
                .font(.body)
                .listRowBackground(rowColor(for: entryModel.level))
                .listRowInsets(EdgeInsets(top: 8, leading: 8 + CGFloat(entryModel.level * 4), bottom: 8, trailing: 8))
            case .photoInline, .edit:
                EmptyView()
            }
                            
            if (isEditor) && (entryModel.sheetType == .item || entryModel.sheetType == .group) {
                deleteButton(onlyIcon: true)
            }
        }
    }
    
    var afterInline: some View {
        ForEach(entryModel.inlineEntries) { inlineSheet in
            switch inlineSheet.sheetType {
            case .dice:
                viewController(for: entryModel.source)?.rowViewer(source: inlineSheet.source, destination: entryModel.destination)
            case .pdf:
                viewController(for: entryModel.source)?.rowViewer(source: inlineSheet.source, destination: entryModel.destination)
            default:
                EmptyView()
            }
        }
    }
    
    func editButton(onlyIcon: Bool) -> some View {
        Button {
            withAnimation {
//                if isEditor {
//                    model.setCurrentItem(source: entry.source, entryId: entry.source.entryId)
//                } else {
//                    model.toggleEdit(entry: entry)
//                }
            }
        } label: {
            Label {
                Text("Edit \(entryModel.name.withoutLink())", bundle: .module)
            } icon: {
                Image(systemName: "square.and.pencil")
                    .opacity(0)
                    .imageScale(.large)
                    .overlay {
//                        Image(systemName: model.isEditing(entry: entry) ? "square.and.pencil" : "pencil")
//                            .imageScale(.large)
//                            .foregroundStyle(.tint, .foreground, .tint)
//                            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
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
//                model.removeEntry(source: entry.source)
//                model.remove(entry: entry)
//                model.updateParent()
            }
        } label: {
            Label {
                Text("Delete \(entryModel.name.withoutLink())", bundle: .module)
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
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: entryModel.source.itemId, childId: entryModel.source.entryId, module: entryModel.source.typeId), showGame: appGameStateModel.isGameRunning, gameModus: appGameStateModel.gameModus)
    }
    
    var text: String {
        if entryModel.description.isEmpty {
            entryModel.name
        } else if entryModel.name.isEmpty {
            entryModel.description
        } else {
            "**" + entryModel.name + "**: " + entryModel.description
        }
    }
}
