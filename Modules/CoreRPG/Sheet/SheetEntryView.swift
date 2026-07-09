// @copyright André Trettin

import SwiftUI

struct SheetEntryView<LinkType: LinkDataTransferable, DetailContent: View>: View {
    init(
        rootModel: SheetRootModel,
        parentModel: SheetModel,
        entryModel: SheetModel,
        isEditor: Bool,
        linkTypes: LinkType.Type,
        detailAction: ((SheetModel) -> Void)? = nil,
        @ViewBuilder detailContent: @escaping (SheetModel) -> DetailContent
    ) {
        self.rootModel = rootModel
        self.parentModel = parentModel
        self.entryModel = entryModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
        self.detailAction = detailAction
        self.detailContent = detailContent
    }

    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    let detailAction: ((SheetModel) -> Void)?
    let detailContent: (SheetModel) -> DetailContent
    
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator

    var body: some View {
        ZStack(alignment: .topLeading) {
            selectionBackgroundButton

            VStack(alignment: .leading) {
                beforeInline

                mainRow

                contentRow

                detailContent(entryModel)

                inlineEditorRow

                afterInline
            }
        }
        .id(entryModel.source.entryId)
        .sheetBorderColor(level: parentModel.level)
        .overlay {
            generatedSelectionBorder
            selectionBorder
        }
        .contentShape(.rect)
        .animation(.easeInOut(duration: 0.2), value: entryModel.isGeneratedSelected)
        .animation(.easeInOut(duration: 0.2), value: entryModel.isSelected)
        .onChange(of: entryModel.name) {
            rootModel.updateParent(parentModel)
        }
        .onChange(of: entryModel.description) {
            rootModel.updateParent(parentModel)
        }
        .applyIf(isEditor || entryModel.isSelected) {
            $0.contextMenuAll {
                SheetEntryEditButton(rootModel: rootModel, entryModel: entryModel, parentModel: parentModel, isEditor: isEditor, onlyIcon: false)
                SheetContextMenuView(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, isEditor: isEditor)
                SheetEntryDeleteButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: false)
                    .tint(.red)
            }
        }
    }
}

private extension SheetEntryView {
    func viewController(for source: ItemRowModel) -> ViewControllable? {
        rootModel.rootManager.rootModel(for: source.typeId)?.viewControllable
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
            if entryModel.isGeneratedAnswer {
                Button("Select answer", systemImage: entryModel.isGeneratedSelected ? "checkmark.circle.fill" : "circle") {
                    toggleGeneratedSelection()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(entryModel.isGeneratedSelected ? .green : .secondary)
                .help("Select answer")
            }

            if (isEditor || entryModel.editType != .none) && (entryModel.sheetType == .item || entryModel.sheetType == .group) {
                SheetEntryEditButton(rootModel: rootModel, entryModel: entryModel, parentModel: parentModel, isEditor: isEditor, onlyIcon: true)
            }
            
            switch entryModel.sheetType {
            case .item, .group:
                if entryModel.isGeneratedAnswer {
                    Button(action: toggleGeneratedSelection) {
                        LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(entryModel.source.entryId ?? entryModel.source.itemId), text: entryModel.name, shareResults: shareResult))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.headline)
                    }
                    .buttonStyle(.plain)
                } else {
                    LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(entryModel.source.entryId ?? entryModel.source.itemId), text: entryModel.name, shareResults: shareResult))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.headline)
                }
                
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

            if let detailAction, canGoDeeper {
                Button("Next Question", systemImage: "questionmark.bubble") {
                    detailAction(entryModel)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!hasDetailContent)
                .help("Next question")
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
                viewController(for: inlineSheet.destination.typeId == .value ? inlineSheet.destination : inlineSheet.source)?.rowViewer(source: inlineSheet.source, destination: inlineSheet.destination)
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

    var canGoDeeper: Bool {
        entryModel.sheetType == .item || entryModel.sheetType == .group
    }
    
    var hasDetailContent: Bool {
        !entryModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !entryModel.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder var generatedSelectionBorder: some View {
        if entryModel.isGeneratedAnswer {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    entryModel.isGeneratedSelected ? Color.green : Color.secondary.opacity(0.25),
                    lineWidth: entryModel.isGeneratedSelected ? 2 : 1
                )
        }
    }

    /// Fills the full row so a plain tap anywhere that isn't already an interactive
    /// element (edit/delete buttons, links inside LinkHighlightTextView) selects it —
    /// or, for an unpersisted AI-generated preview row, commits it into a real entry.
    /// Placed behind the row content, so those existing controls keep first hit-test priority.
    /// The explicit frame + contentShape guarantee the whole row is tappable, independent
    /// of how the sibling row content happens to size the surrounding ZStack.
    var selectionBackgroundButton: some View {
        Button {
            if entryModel.isGeneratedAnswer {
                rootModel.commitGeneratedEntry(entryModel, parent: parentModel)
            } else {
                rootModel.setSelected(entryModel, parent: parentModel)
            }
        } label: {
            Rectangle().fill(.clear)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel(Text("Select \(entryModel.name.withoutLink())", bundle: .module))
    }

    @ViewBuilder var selectionBorder: some View {
        if entryModel.isSelected {
            let tint = entryModel.source.typeId.tint
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.08))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [tint, tint.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
            }
            .shadow(color: tint.opacity(0.35), radius: 6)
        }
    }

    func toggleGeneratedSelection() {
        withAnimation {
            entryModel.isGeneratedSelected.toggle()
        }
    }
}
