// @copyright André Trettin

import SwiftUI

struct SheetEntryView<LinkType: LinkDataTransferable, DetailContent: View>: View {
    init(
        rootModel: SheetRootModel,
        parentModel: SheetModel,
        entryModel: SheetModel,
        isEditor: Bool,
        linkTypes: LinkType.Type,
        generatedAcceptanceNamespace: Namespace.ID,
        detailAction: ((SheetModel) -> Void)? = nil,
        @ViewBuilder detailContent: @escaping (SheetModel) -> DetailContent
    ) {
        self.rootModel = rootModel
        self.parentModel = parentModel
        self.entryModel = entryModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
        self.generatedAcceptanceNamespace = generatedAcceptanceNamespace
        self.detailAction = detailAction
        self.detailContent = detailContent
    }

    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    let generatedAcceptanceNamespace: Namespace.ID
    let detailAction: ((SheetModel) -> Void)?
    let detailContent: (SheetModel) -> DetailContent
    
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let geometryMatch = rootModel.sheetRowGeometryMatch(
            for: entryModel,
            parent: parentModel
        )

        ZStack(alignment: .topLeading) {
            if !usesGeneratedContextMenu && !entryModel.isReviewPlaceholder {
                selectionBackgroundButton
            }

            VStack(alignment: .leading) {
                if entryModel.isReviewPlaceholder, let reviewModel = entryModel.entryReviewModel {
                    SheetEntryReviewPlaceholderView(
                        entryModel: entryModel,
                        reviewModel: reviewModel
                    )
                } else {
                    beforeInline

                    mainRow

                    contentRow
                        .allowsHitTesting(!entryModel.isGeneratedAnswer)

                    detailContent(entryModel)

                    inlineEditorRow

                    afterInline
                }

                if let reviewModel = entryModel.entryReviewModel, reviewModel.hasDifferences {
                    SheetEntryReviewAlternativesView(reviewModel: reviewModel)
                }
            }
        }
        .id(entryModel.source.entryId ?? entryModel.source.itemId)
        .sheetBorderColor(level: parentModel.level)
        .overlay {
            ZStack {
                generatedSelectionBorder
                selectionBorder
            }
            .allowsHitTesting(false)
        }
        .matchedGeometryEffect(
            id: geometryMatch.id,
            in: generatedAcceptanceNamespace,
            properties: .frame,
            anchor: .center,
            isSource: geometryMatch.isSource
        )
        .contentShape(.rect)
        .zIndex(entryModel.isGeneratedAnswer ? 1 : 0)
        .animation(accessibilityReduceMotion ? nil : .smooth, value: entryModel.isGeneratedAnswer)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: entryModel.isGeneratedSelected)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: entryModel.isSelected)
        .onChange(of: entryModel.name) {
            rootModel.updateParent(parentModel)
        }
        .onChange(of: entryModel.description) {
            rootModel.updateParent(parentModel)
        }
        .applyIf(!entryModel.isReviewPlaceholder && !entryModel.isGeneratedAnswer && (isEditor || entryModel.isSelected)) {
            $0.contextMenuAll {
                SheetEntryEditButton(rootModel: rootModel, entryModel: entryModel, parentModel: parentModel, isEditor: isEditor, onlyIcon: false)
                SheetContextMenuView(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, isEditor: isEditor)
                SheetEntryDeleteButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: false)
                    .tint(.red)
            }
        }
        .applyIf(usesGeneratedContextMenu) {
            $0
                .contextMenuAll {
                    GeneratedSheetEntryContextMenu(
                        canRefine: rootModel.canRefineGeneratedPreview(
                            entryModel,
                            in: parentModel
                        ),
                        takeOverAction: takeOverGeneratedEntry,
                        refineAction: refineGeneratedEntry,
                        deleteAction: deleteGeneratedEntry
                    )
                }
                .accessibilityAction(named: Text("Take Over", bundle: .module)) {
                    takeOverGeneratedEntry()
                }
                .accessibilityAction(named: Text("Refine with AI", bundle: .module)) {
                    refineGeneratedEntry()
                }
                .accessibilityAction(named: Text("Delete Generated Content", bundle: .module)) {
                    deleteGeneratedEntry()
                }
        }
    }
}

private extension SheetEntryView {
    func viewController(for source: ItemRowModel) -> ViewControllable? {
        rootModel.rootManager.rootModel(for: source.typeId)?.viewControllable
    }
    
    @ViewBuilder var beforeInline: some View {
        if entryModel.entryReviewModel != nil {
            ForEach(entryModel.inlineEntries) { inlineSheet in
                SheetEntryReviewInlineSnapshotView(sheetModel: inlineSheet)
            }
        } else {
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
    }

    var mainRow: some View {
        HStack {
            if usesGeneratedContextMenu {
                generatedTakeOverButton
            } else if entryModel.isGeneratedAnswer {
                Image(systemName: generatedIndicatorSystemImage)
                .foregroundStyle(entryModel.isGeneratedSelected ? .green : .secondary)
                .accessibilityHidden(true)
            }

            refineWithAIButton

            if !entryModel.isGeneratedAnswer && (isEditor || entryModel.editType != .none) && (entryModel.sheetType == .item || entryModel.sheetType == .group) {
                SheetEntryEditButton(rootModel: rootModel, entryModel: entryModel, parentModel: parentModel, isEditor: isEditor, onlyIcon: true)
            }

            Group {
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
            }
            .allowsHitTesting(!entryModel.isGeneratedAnswer)
                            
            if !entryModel.isGeneratedAnswer && isEditor && (entryModel.sheetType == .item || entryModel.sheetType == .group) {
                SheetEntryDeleteButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: true)
            }

            if usesGeneratedContextMenu {
                generatedDeleteButton
            }

            if !entryModel.isGeneratedAnswer,
               let reviewModel = entryModel.entryReviewModel,
               reviewModel.hasDifferences {
                SheetEntryReviewButton(model: reviewModel)
            }

            if !entryModel.isGeneratedAnswer, let detailAction, canGoDeeper {
                Button {
                    detailAction(entryModel)
                } label: {
                    Label {
                        Text("Next Question", bundle: .module)
                    } icon: {
                        Image(systemName: "questionmark.bubble")
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!hasDetailContent)
                .help(Text("Next question", bundle: .module))
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
    
    @ViewBuilder var afterInline: some View {
        if entryModel.entryReviewModel == nil {
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

    var usesGeneratedContextMenu: Bool {
        isEditor && entryModel.isGeneratedAnswer
    }

    @ViewBuilder var refineWithAIButton: some View {
        if !entryModel.isGeneratedAnswer && rootModel.isAIModeActive && hasDetailContent {
            Button(action: refineExistingEntry) {
                if isRefiningWithAI {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label {
                        Text("Refine with AI", bundle: .module)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(rootModel.pendingGenerationRequest != nil)
            .accessibilityLabel(Text("Refine with AI", bundle: .module))
            .accessibilityValue(
                isRefiningWithAI
                    ? Text("Generating", bundle: .module)
                    : Text("Ready", bundle: .module)
            )
            .help(Text("Refine this content with AI", bundle: .module))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    var isRefiningWithAI: Bool {
        rootModel.pendingGenerationRequest?.focus.selectedModelID == entryModel.id
    }

    var generatedTakeOverButton: some View {
        Button(action: takeOverGeneratedEntry) {
            Label {
                Text("Take Over", bundle: .module)
            } icon: {
                Image(systemName: "sparkles")
            }
        }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(.green)
            .help(Text("Take over generated content", bundle: .module))
    }

    var generatedDeleteButton: some View {
        Button(role: .destructive, action: deleteGeneratedEntry) {
            Label {
                Text("Delete Generated Content", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .help(Text("Delete generated content", bundle: .module))
    }

    @ViewBuilder var generatedSelectionBorder: some View {
        if entryModel.isGeneratedAnswer {
            let green = Color.green
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(green.opacity(entryModel.isGeneratedSelected ? 0.14 : 0.06))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [green, .mint.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: entryModel.isGeneratedSelected ? 3 : 2
                    )
            }
            .shadow(
                color: green.opacity(entryModel.isGeneratedSelected ? 0.35 : 0.2),
                radius: entryModel.isGeneratedSelected ? 6 : 4
            )
            .transition(.scale(scale: 0.98).combined(with: .opacity))
        }
    }

    /// Fills regular and non-editor rows so a plain tap anywhere that isn't already an
    /// interactive element selects it. Editor previews intentionally omit this button
    /// because they expose explicit Take Over/Delete controls (and a context menu).
    /// Placed behind the row content, so those existing controls keep first hit-test priority.
    /// The explicit frame + contentShape guarantee the whole row is tappable, independent
    /// of how the sibling row content happens to size the surrounding ZStack.
    var selectionBackgroundButton: some View {
        Button {
            performPrimaryAction()
        } label: {
            Rectangle().fill(.clear)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel(primaryActionAccessibilityLabel)
        .accessibilityValue(generatedSelectionAccessibilityValue)
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
        withAnimation(accessibilityReduceMotion ? nil : .smooth) {
            entryModel.isGeneratedSelected.toggle()
        }
    }

    func performPrimaryAction() {
        if entryModel.isGeneratedAnswer {
            toggleGeneratedSelection()
        } else {
            rootModel.setSelected(entryModel, parent: parentModel)
        }
    }

    func takeOverGeneratedEntry() {
        guard usesGeneratedContextMenu else { return }

        let previewID = entryModel.source.entryId ?? entryModel.source.itemId
        let parentModelID = parentModel.id
        let animation: Animation? = accessibilityReduceMotion ? nil : .smooth
        _ = withAnimation(animation, completionCriteria: .removed) {
            rootModel.commitGeneratedEntry(entryModel, parent: parentModel)
        } completion: {
            rootModel.finishGeneratedAcceptanceTransition(
                previewID: previewID,
                parentModelID: parentModelID
            )
        }
    }

    func refineExistingEntry() {
        let animation: Animation? = accessibilityReduceMotion ? nil : .smooth
        _ = withAnimation(animation) {
            rootModel.queueGeneration(
                from: entryModel,
                parent: parentModel,
                module: parentModel.source.typeId
            )
        }
    }

    func refineGeneratedEntry() {
        guard usesGeneratedContextMenu else { return }
        let animation: Animation? = accessibilityReduceMotion ? nil : .smooth
        _ = withAnimation(animation) {
            rootModel.refineGeneratedPreview(entryModel, in: parentModel)
        }
    }

    func deleteGeneratedEntry() {
        guard usesGeneratedContextMenu else { return }
        let animation: Animation? = accessibilityReduceMotion ? nil : .smooth
        _ = withAnimation(animation) {
            rootModel.discardGeneratedPreview(entryModel, in: parentModel)
        }
    }

    var generatedIndicatorSystemImage: String {
        entryModel.isGeneratedSelected ? "checkmark.circle.fill" : "circle"
    }

    var primaryActionAccessibilityLabel: Text {
        if entryModel.isGeneratedAnswer {
            if isEditor {
                Text("Use generated content \(entryModel.name.withoutLink())", bundle: .module)
            } else {
                Text("Select answer \(entryModel.name.withoutLink())", bundle: .module)
            }
        } else {
            Text("Select \(entryModel.name.withoutLink())", bundle: .module)
        }
    }

    var generatedSelectionAccessibilityValue: Text {
        guard entryModel.isGeneratedAnswer && !isEditor else { return Text(verbatim: "") }
        return entryModel.isGeneratedSelected
            ? Text("Selected", bundle: .module)
            : Text("Not selected", bundle: .module)
    }
}

#Preview("Sheet Entry Direct") {
    @Previewable @Namespace var namespace
    SheetEntryView(
        rootModel: .fake,
        parentModel: .empty,
        entryModel: .empty,
        isEditor: true,
        linkTypes: EmptyLinkTransferable.self,
        generatedAcceptanceNamespace: namespace,
        detailContent: { _ in EmptyView() }
    )
}
