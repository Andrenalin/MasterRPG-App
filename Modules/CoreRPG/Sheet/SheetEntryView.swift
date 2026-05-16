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
        .id(entryModel.source.entryId)
        .sheetBorderColor(level: parentModel.level)
        .contentShape(.rect)
        .onChange(of: entryModel.name) {
            rootModel.updateParent(parentModel)
        }
        .onChange(of: entryModel.description) {
            rootModel.updateParent(parentModel)
        }
        .applyIf(isEditor) {
            $0.contextMenuAll {
                SheetEntryEditButton(rootModel: rootModel, entryModel: entryModel, isEditor: isEditor, onlyIcon: false)
                SheetContextMenuView(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, isEditor: isEditor)
                SheetEntryDeleteButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: false)
                    .tint(.red)
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
                // Use inlineSheet.source (the photo item) not entryModel.source (the parent entry)
                viewController(for: inlineSheet.source)?.rowViewer(source: inlineSheet.source, destination: inlineSheet.destination)
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
                LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(entryModel.source.entryId ?? entryModel.source.itemId), text: entryModel.name, shareResults: shareResult))
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
                    LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(entryModel.source.entryId ?? entryModel.source.itemId), text: audioDisplayText, shareResults: shareResult))
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
                    LinkHighlightTextView(model: rootModel.linkTextModel(for: .entryContent(entryModel.source.entryId ?? entryModel.source.itemId), text: entryModel.description, shareResults: shareResult))
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
                // Use inlineSheet.source for both viewController lookup and rowViewer
                viewController(for: inlineSheet.source)?.rowViewer(source: inlineSheet.source, destination: inlineSheet.destination)
            case .pdf:
                // Use inlineSheet.source for both viewController lookup and rowViewer
                viewController(for: inlineSheet.source)?.rowViewer(source: inlineSheet.source, destination: inlineSheet.destination)
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
