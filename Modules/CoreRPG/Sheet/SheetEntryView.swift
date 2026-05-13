// @copyright André Trettin

import SwiftUI

struct SheetEntryView<LinkType: LinkDataTransferable>: View {
    init(rootModel: SheetRootModel, parentModel: SheetModel, entryModel: SheetModel, isEditor: Bool, linkTypes: LinkType.Type) {
        self.rootModel = rootModel
        self.parentModel = parentModel
        self.entryModel = entryModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }

    let rootModel: SheetRootModel
    let parentModel: SheetModel
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
            
            contentRow
            
            inlineEditorRow
            
            afterInline
        }
        .sheetBorderColor(level: parentModel.level)
        .contentShape(.rect)
        .moveDisabled(entryModel.sheetType != .item && entryModel.sheetType != .group)
        .onChange(of: entryModel.name) {
            rootModel.updateParent(parentModel)
        }
        .onChange(of: entryModel.description) {
            rootModel.updateParent(parentModel)
        }
#if !os(tvOS)
        .applyIf(isEditor && entryModel.sheetType == .item) {
            $0.dropDestination(for: linkTypes, isEnabled: entryModel.sheetType != .group) { items, _ in
                items.forEach {
                    rootModel.addLink(link: $0.name, module: $0.module, itemId: $0.itemId, entryId: $0.entryId, to: entryModel, in: parentModel)
                }
            }
        }
#endif
        .contextMenuAll {
            SheetEntryEditButton(rootModel: rootModel, entryModel: entryModel, isEditor: isEditor, onlyIcon: false)
            SheetContextMenuView(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, isEditor: isEditor)
            SheetEntryDeleteButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: false)
                .tint(.red)
        }

        ForEach(entryModel.entries) { subEntry in
            if let root = rootModel.rootController(for: subEntry.source.typeId), subEntry.isShown {
                SheetView(root: root, rootModel: rootModel, sheetModel: subEntry, isEditor: isEditor, linkTypes: linkTypes)
                    .padding(.leading, 2)
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
            case .photo:
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
                SheetEntryEditButton(rootModel: rootModel, entryModel: entryModel, isEditor: isEditor, onlyIcon: true)
            }
            
            switch entryModel.sheetType {
            case .item, .group:
                LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(entryModel.id), text: entryModel.name, shareResults: shareResult))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.headline)
                
            case .dice:
                viewController(for: entryModel.source)?.rowViewer(source: entryModel.source, destination: entryModel.destination)
            case .pdf, .photo, .space, .weather:
                viewController(for: entryModel.source)?.rowViewer(source: entryModel.source, destination: entryModel.destination)
                    .frame(height: 256)

            case .audio:
                HStack {
                    viewController(for: entryModel.source)?.rowViewer(source: entryModel.source, destination: entryModel.destination)
                    LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(entryModel.id), text: audioDisplayText, shareResults: shareResult))
                }
                .font(.body)
            }
                            
            if isEditor && (entryModel.sheetType == .item || entryModel.sheetType == .group) {
                SheetEntryDeleteButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: true)
            }
        }
    }

    @ViewBuilder var contentRow: some View {
        if !entryModel.description.isEmpty {
            HStack {
                if entryModel.editType.isEditable {
                    Image(systemName: entryModel.editType.icon)
                        .imageScale(.small)
                        .foregroundStyle(.foreground, .tint)
                        .padding(4)
                        .background {
                            Circle().stroke(entryModel.source.typeId.tint.opacity(0.3))
                        }
                }
                switch entryModel.sheetType {
                case .item:
                    LinkHighlightTextView(model: rootModel.linkTextModel(for: .entryContent(entryModel.id), text: entryModel.description, shareResults: shareResult))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.body)
                default:
                    EmptyView()
                }
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
    
    @ViewBuilder var inlineEditorRow: some View {
        if !isEditor && (entryModel.isEditing && entryModel.editType != .none), let entryDataEditable = rootModel.entryDataEditable(for: entryModel.source) {
            // Show inline editor when in edit mode (not available in editor mode)
            InlineEditorView(entryDataEditable: entryDataEditable, updateHandler: { text in
                rootModel.updateSheetModel(entryModel: entryModel, updatedText: text)
            }, entry: entryModel)
        }
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

    var audioDisplayText: String {
        if entryModel.description.isEmpty {
            entryModel.name
        } else if entryModel.name.isEmpty {
            entryModel.description
        } else {
            "**\(entryModel.name)**: \(entryModel.description)"
        }
    }
}
