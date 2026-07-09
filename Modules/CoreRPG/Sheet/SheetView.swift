// @copyright André Trettin

import SwiftUI

struct SheetView<LinkType: LinkDataTransferable, DetailContent: View>: View {
    init(
        root: ItemRootController,
        rootModel: SheetRootModel,
        sheetModel: SheetModel,
        isEditor: Bool = false,
        linkTypes: LinkType.Type = LinkDiceData.self,
        detailAction: ((SheetModel) -> Void)? = nil,
        @ViewBuilder detailContent: @escaping (SheetModel) -> DetailContent
    ) {
        self.root = root
        self.rootModel = rootModel
        self.sheetModel = sheetModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
        self.detailAction = detailAction
        self.detailContent = detailContent
    }
    
    let root: ItemRootController
    let rootModel: SheetRootModel
    let sheetModel: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    let detailAction: ((SheetModel) -> Void)?
    let detailContent: (SheetModel) -> DetailContent
    
    @State private var dropTargetEntryId: String?
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        if sheetModel.showHeader || isEditor {
            GameShareView(root: root, itemId: sheetModel.source.itemId) {
                nameRow
            }
            .sheetBorderColor(level: sheetModel.level)
            
            if !sheetModel.isFolded {
                inlineRows
                
                secondaryRow
                    .sheetBorderColor(level: sheetModel.level)
            }
        }
        
        if !sheetModel.isFolded {
            entryRows
        }
        
        endRow
            .onChange(of: rootModel.editorModel.entryId) { previousEntryId, currentEntryId in
                guard previousEntryId != currentEntryId else { return }
                rootModel.update(sheetModel: sheetModel, previousEntryId: previousEntryId, currentEntryId: currentEntryId)
            }
    }
}

private extension SheetView {
    var nameRow: some View {
        ZStack(alignment: .topLeading) {
            selectionBackgroundButton

            HStack {
                if isEditor && sheetModel.canAdd {
                    SheetEntryAddButton(rootModel: rootModel, parentModel: sheetModel, onlyIcon: true)
                }

                LinkHighlightTextView(model: rootModel.linkTextModel(for: .item(sheetModel.source.itemId), text: sheetModel.name))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.title)

                if let detailAction {
                    Button("Next Question", systemImage: "questionmark.bubble") {
                        detailAction(sheetModel)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(!sheetModel.hasDetailContent)
                    .help("Next question")
                }
            }
        }
        .overlay {
            selectionBorder
        }
        .contentShape(.rect)
        .animation(.easeInOut(duration: 0.2), value: sheetModel.isSelected)
        .applyIf((isEditor && sheetModel.canAdd) || sheetModel.isSelected) {
            $0.contextMenuAll {
                SheetContextMenuView(rootModel: rootModel, parentModel: sheetModel, entryModel: sheetModel, isEditor: isEditor)
            }
        }
    }

    /// Fills the name row so a plain tap anywhere that isn't already an interactive
    /// element (add button, links inside LinkHighlightTextView, "Next Question") selects it.
    /// The explicit frame + contentShape guarantee the whole row is tappable, independent
    /// of how the sibling row content happens to size the surrounding ZStack.
    var selectionBackgroundButton: some View {
        Button {
            rootModel.setSelected(sheetModel, parent: sheetModel)
        } label: {
            Rectangle().fill(.clear)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel(Text("Select \(sheetModel.name.withoutLink())", bundle: .module))
    }

    @ViewBuilder var selectionBorder: some View {
        if sheetModel.isSelected {
            let tint = sheetModel.source.typeId.tint
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
    
    var inlineRows: some View {
        ForEach(sheetModel.inlineEntries) { inlineEntry in
            // Display inline entries directly without SheetEntryView wrapper
            // to avoid triggering beforeInline/afterInline recursion
            Group {
                viewController(for: inlineEntry.source)?.rowViewer(source: inlineEntry.source, destination: inlineEntry.destination)
            }
            .applyIf(inlineEntry.sheetType == .photo) {
                $0.frame(height: 160)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .applyIf(inlineEntry.sheetType != .photo) {
                $0.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    func viewController(for source: ItemRowModel) -> ViewControllable? {
        rootModel.rootController(for: source.typeId)?.viewControllable
    }
    
    @ViewBuilder
    var secondaryRow: some View {
        if let description = rootModel.description(for: sheetModel), !description.isEmpty {
            LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(sheetModel.source.entryId ?? sheetModel.source.itemId), text: description))
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.subheadline)
        }
    }
    
    @ViewBuilder var entryRows: some View {
        entryRows(for: regularEntries(in: sheetModel.entries))

        detailContent(sheetModel)

        entryRows(for: generatedEntries(in: sheetModel.entries))
    }

    @ViewBuilder func entryRows(for entries: [SheetModel]) -> some View {
        ForEach(entries) { entry in
            SheetEntryView(rootModel: rootModel, parentModel: sheetModel, entryModel: entry, isEditor: isEditor, linkTypes: linkTypes, detailAction: detailAction, detailContent: detailContent)
                .frame(maxWidth: .infinity, alignment: .leading)
                // .draggable() below installs its own gesture recognizer that can win
                // arbitration over the nested selection Button in editor mode, so taps
                // silently stop reaching it. simultaneousGesture is guaranteed to coexist
                // with .draggable's gesture rather than compete with it.
                .simultaneousGesture(TapGesture().onEnded {
                    if entry.isGeneratedAnswer {
                        rootModel.commitGeneratedEntry(entry, parent: sheetModel)
                    } else {
                        rootModel.setSelected(entry, parent: sheetModel)
                    }
                })
#if !os(tvOS)
                .applyIf(isEditor) {
                    $0
                        .background(dropTargetEntryId == entry.id ? Color.accentColor.opacity(0.2) : Color.clear)
                        .draggable(for: entry.source.typeId, itemId: entry.source.itemId, entryId: entry.source.entryId, name: entry.name.withoutLink(), isMove: true)
                        .dropDestination(for: linkTypes) { items, location in
                            handleDrop(items: items, targetEntry: entry)
                        } isTargeted: { isTargeted in
                            dropTargetEntryId = isTargeted ? entry.id : nil
                        }
                }
#endif

            let visibleSubEntries = visibleEntries(in: entry.entries)
            ForEach(visibleSubEntries) { subEntry in
                if subEntry.isGeneratedAnswer {
                    GeneratedSheetEntryTreeView(rootModel: rootModel, parentModel: entry, entryModel: subEntry, isEditor: isEditor, linkTypes: linkTypes, detailAction: detailAction, detailContent: detailContent)
                        .padding(.leading, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let root = rootModel.rootController(for: subEntry.source.typeId), subEntry.isShown {
                    SheetView(root: root, rootModel: rootModel, sheetModel: subEntry, isEditor: isEditor, linkTypes: linkTypes, detailAction: detailAction, detailContent: detailContent)
                        .padding(.leading, 2)
                }
            }
        }
    }

    func visibleEntries(in entries: [SheetModel]) -> [SheetModel] {
        entries.filter { !$0.isHidden && !$0.isGeneratedHidden }
    }

    func regularEntries(in entries: [SheetModel]) -> [SheetModel] {
        visibleEntries(in: entries).filter { !$0.isGeneratedAnswer }
    }

    func generatedEntries(in entries: [SheetModel]) -> [SheetModel] {
        visibleEntries(in: entries).filter(\.isGeneratedAnswer)
    }

    func handleDrop(items: [LinkType], targetEntry: SheetModel) -> Bool {
        rootModel.handleDrop(items: items, targetEntry: targetEntry, parentModel: sheetModel)
    }
    
    var endRow: some View {
        Color.accentColor.opacity(0.3)
            .frame(height: 8)
    }
}

private struct GeneratedSheetEntryTreeView<LinkType: LinkDataTransferable, DetailContent: View>: View {
    init(
        rootModel: SheetRootModel,
        parentModel: SheetModel,
        entryModel: SheetModel,
        isEditor: Bool,
        linkTypes: LinkType.Type,
        detailAction: ((SheetModel) -> Void)?,
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

    var body: some View {
        SheetEntryView(
            rootModel: rootModel,
            parentModel: parentModel,
            entryModel: entryModel,
            isEditor: isEditor,
            linkTypes: linkTypes,
            detailAction: detailAction,
            detailContent: detailContent
        )
        .frame(maxWidth: .infinity, alignment: .leading)

        ForEach(visibleChildEntries) { childEntry in
            if childEntry.isGeneratedAnswer {
                GeneratedSheetEntryTreeView(
                    rootModel: rootModel,
                    parentModel: entryModel,
                    entryModel: childEntry,
                    isEditor: isEditor,
                    linkTypes: linkTypes,
                    detailAction: detailAction,
                    detailContent: detailContent
                )
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let root = rootModel.rootController(for: childEntry.source.typeId), childEntry.isShown {
                SheetView(
                    root: root,
                    rootModel: rootModel,
                    sheetModel: childEntry,
                    isEditor: isEditor,
                    linkTypes: linkTypes,
                    detailAction: detailAction,
                    detailContent: detailContent
                )
                .padding(.leading, 2)
            }
        }
    }

    private var visibleChildEntries: [SheetModel] {
        entryModel.entries.filter { !$0.isHidden && !$0.isGeneratedHidden }
    }
}

private extension SheetModel {
    var hasDetailContent: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
