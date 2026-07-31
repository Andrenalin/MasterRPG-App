// @copyright André Trettin

import SwiftUI

struct SheetView<LinkType: LinkDataTransferable>: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.networkActions) private var networkActions
    @Environment(\.itemGenerationAction) private var itemGenerationAction
    @Environment(AppGameStateModel.self) private var appGameStateModel
    
    init(
        root: ItemRootController,
        rootModel: SheetRootModel,
        sheetModel: SheetModel,
        isEditor: Bool = false,
        linkTypes: LinkType.Type = LinkDiceData.self
    ) {
        self.root = root
        self.rootModel = rootModel
        self.sheetModel = sheetModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }
    
    let root: ItemRootController
    let rootModel: SheetRootModel
    let sheetModel: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    
    @State private var dropTargetEntryId: UUID?
    
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
            HStack {
                if isEditor && sheetModel.canAdd {
                    SheetEntryAddButton(rootModel: rootModel, parentModel: sheetModel, onlyIcon: true)
                }
                
                LinkHighlightTextView(
                    model: rootModel.linkTextModel(
                        for: .item(sheetModel.source.itemId),
                        text: sheetModel.name,
                        shareResults: shareResult
                    )
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.title)
            }
        }
        .background {
            selectionBackgroundButton
        }
        .overlay {
            selectionBorder
                .allowsHitTesting(false)
        }
        .contentShape(.rect)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: sheetModel.isSelected)
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityLabel(Text("Select \(sheetModel.name.withoutLink())", bundle: .module))
    }
    
    @ViewBuilder var selectionBorder: some View {
        if sheetModel.isSelected {
            let tint = theme.tint(for: sheetModel.source.typeId)
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
                    .clipShape(.rect(cornerRadius: 16))
            }
            .applyIf(inlineEntry.sheetType != .photo) {
                $0.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    func viewController(for source: ItemRowModel) -> ViewControllable? {
        rootModel.rootController(for: source.typeId)?.viewControllable
    }
    
    var shareResult: ShareValueResult {
        ShareValueResult(
            networkActions: networkActions,
            resultCategory: ResultCategory(source: sheetModel.source),
            showGame: appGameStateModel.isGameRunning,
            gameModus: appGameStateModel.gameModus,
            generationAction: itemGenerationAction
        )
    }
    
    @ViewBuilder
    var secondaryRow: some View {
        if let description = rootModel.description(for: sheetModel), !description.isEmpty {
            LinkHighlightTextView(
                model: rootModel.linkTextModel(
                    for: .itemContent(sheetModel.source.itemId),
                    text: description,
                    shareResults: shareResult
                )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.subheadline)
        }
    }
    
    @ViewBuilder var entryRows: some View {
        ForEach(sheetModel.entries) { entry in
            if !entry.isHidden {
                row(entry: entry)
            }
        }
        
        ForEach(sheetModel.aiGeneratedEntries) { entry in
            row(entry: entry)
                .transition(.generatedSheetEntry)
        }
        if let preview = sheetModel.aiPreviewEntry {
            row(entry: preview)
                .transition(.generatedSheetEntry)
        }
    }
    
    @ViewBuilder func row(entry: SheetModel) -> some View {
        SheetEntryView(rootModel: rootModel, parentModel: sheetModel, entryModel: entry, isEditor: isEditor, linkTypes: linkTypes)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        
        ForEach(entry.entries) { subEntry in
            if let root = rootModel.rootController(for: subEntry.source.typeId), subEntry.isShown {
                SheetView(root: root, rootModel: rootModel, sheetModel: subEntry, isEditor: isEditor, linkTypes: linkTypes)
                    .padding(.leading, 2)
            }
        }
    }
    
    func handleDrop(items: [LinkType], targetEntry: SheetModel) -> Bool {
        rootModel.handleDrop(items: items, targetEntry: targetEntry, parentModel: sheetModel)
    }
    
    var endRow: some View {
        Color.accentColor.opacity(0.3)
            .frame(height: 8)
    }
}

private extension AnyTransition {
    static var persistedSheetEntry: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.98).combined(with: .opacity),
            removal: .scale(scale: 0.99).combined(with: .opacity)
        )
    }
    
    static var generatedSheetEntry: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .scale(scale: 0.98).combined(with: .opacity)
        )
    }
}

#Preview("Sheet View Direct") {
    @Previewable @Namespace var namespace
    let fixture = FakeItemRootControllerFixture()
    ScrollView {
        SheetView(
            root: fixture.root,
            rootModel: fixture.sheetRootModel,
            sheetModel: fixture.sheetRootModel.sheetModel,
            isEditor: true,
            linkTypes: EmptyLinkTransferable.self
        )
        .padding()
    }
    .environment(AppGameStateModel())
}
