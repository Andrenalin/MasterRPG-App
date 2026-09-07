// @copyright André Trettin

import SwiftUI

/// Leading indent applied per nesting level when a sub-entry's own linked sheet is
/// rendered recursively (see `SheetEntryRowsView.row(entry:)`) — deliberately smaller than any
/// system spacing token, so it's kept as a named constant instead of a magic literal.
/// See CODE_AUDIT_Sheet §8.1.
private let nestedSheetLeadingInset: CGFloat = 2

struct SheetView<LinkType: LinkDataTransferable>: View {
    @Environment(\.networkActions) private var networkActions
    @Environment(\.itemGenerationAction) private var itemGenerationAction
    @Environment(AppGameStateModel.self) private var appGameStateModel
    
    init(
        root: ItemRootController,
        rootModel: SheetRootModel,
        sheetModel: SheetModel,
        isEditor: Bool = false,
        linkTypes: LinkType.Type = LinkDiceData.self,
        focusedEntryId: FocusState<UUID?>.Binding
    ) {
        self.root = root
        self.rootModel = rootModel
        self.sheetModel = sheetModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
        self.focusedEntryId = focusedEntryId
    }

    let root: ItemRootController
    let rootModel: SheetRootModel
    let sheetModel: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    let focusedEntryId: FocusState<UUID?>.Binding
    
    @State private var dropTargetEntryId: UUID?
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        if sheetModel.showHeader || isEditor {
            GameShareView(root: root, itemId: sheetModel.source.itemId) {
                SheetNameRowView(rootModel: rootModel, sheetModel: sheetModel, isEditor: isEditor, focusedEntryId: focusedEntryId, shareResult: shareResult)
            }
            .sheetBorderColor(level: sheetModel.level)

            if !sheetModel.isFolded {
                SheetInlineRowsView(sheetModel: sheetModel, rootModel: rootModel)

                SheetSecondaryRowView(rootModel: rootModel, sheetModel: sheetModel, shareResult: shareResult)
                    .sheetBorderColor(level: sheetModel.level)
            }
        }

        if !sheetModel.isFolded {
            SheetEntryRowsView(rootModel: rootModel, sheetModel: sheetModel, isEditor: isEditor, linkTypes: linkTypes, focusedEntryId: focusedEntryId, dropTargetEntryId: $dropTargetEntryId)
        }

        SheetEndRowView()
            .onChange(of: rootModel.editorModel.entryId) { previousEntryId, currentEntryId in
                guard previousEntryId != currentEntryId else { return }
                rootModel.update(sheetModel: sheetModel, previousEntryId: previousEntryId, currentEntryId: currentEntryId)
            }
    }
}

private extension SheetView {
    var shareResult: ShareValueResult {
        ShareValueResult(
            networkActions: networkActions,
            resultCategory: ResultCategory(source: sheetModel.source),
            showGame: appGameStateModel.isGameRunning,
            gameModus: appGameStateModel.gameModus,
            generationAction: itemGenerationAction
        )
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.2)

/// A `Button` wrapping the row content directly, not an invisible `.background()` button
/// behind it — see `SheetEntryView` for the full rationale (same fix, same root cause).
private struct SheetNameRowView: View {
    let rootModel: SheetRootModel
    let sheetModel: SheetModel
    let isEditor: Bool
    let focusedEntryId: FocusState<UUID?>.Binding
    let shareResult: ShareValueResult

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button {
            rootModel.setSelected(sheetModel, parent: sheetModel)
        } label: {
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
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focused(focusedEntryId, equals: sheetModel.id)
        // Covers focus reaching this row without going through the tap action (e.g. Tab-key
        // navigation onto it, or the keyboard-arrow sync in SheetRootView) — keeps focusId and
        // selectedId the same regardless of how focus got here. This is also the sole place
        // that requests a scroll: only genuine focus activation should move the scroll view —
        // see `SheetRootModel.setSelected`. The scroll request is unconditional on focus
        // arriving here (not folded into the `setSelected` guard below), since arrow-key
        // navigation already updates `selectedEntryId` before this focus sync runs.
        .onChange(of: focusedEntryId.wrappedValue) {
            guard focusedEntryId.wrappedValue == sheetModel.id else { return }
            rootModel.handleFocusActivation(entryModel: sheetModel, parent: sheetModel)
        }
        .accessibilityLabel(Text("Select \(sheetModel.name.withoutLink())", bundle: .module))
        .overlay {
            SheetSelectionBorderView(sheetModel: sheetModel)
                .allowsHitTesting(false)
        }
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: sheetModel.isSelected)
        // See SheetEntryView's matching comment: the context menu carries
        // structural edit actions, only available where edits actually persist.
        .applyIf(rootModel.persistsEdits && sheetModel.canAdd) {
            $0.contextMenuAll {
                SheetContextMenuView(rootModel: rootModel, parentModel: sheetModel, entryModel: sheetModel, isEditor: isEditor)
            }
        }
    }
}

private struct SheetSelectionBorderView: View {
    let sheetModel: SheetModel

    @Environment(\.appTheme) private var theme

    var body: some View {
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
}

private struct SheetInlineRowsView: View {
    let sheetModel: SheetModel
    let rootModel: SheetRootModel

    var body: some View {
        ForEach(sheetModel.inlineEntries) { inlineEntry in
            // Display inline entries directly without SheetEntryView wrapper
            // to avoid triggering beforeInline/afterInline recursion
            Group {
                viewController(for: inlineEntry.source)?.rowViewer(
                    source: inlineEntry.source,
                    destination: inlineEntry.destination,
                    sourceModel: resolvedModel(for: inlineEntry.source, rootManager: rootModel.rootManager),
                    destinationModel: resolvedModel(for: inlineEntry.destination, rootManager: rootModel.rootManager)
                )
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

    private func viewController(for source: ItemRowModel) -> ViewControllable? {
        rootModel.rootController(for: source.typeId)?.viewControllable
    }

    /// Resolves `row`'s model once here — the `ForEach` above already
    /// subscribes to this module's `itemData` regardless (it needs to know
    /// about additions/removals), so doing the read here instead of inside
    /// `rowViewer`'s per-row leaf keeps that one, expected subscription at
    /// the list boundary. See CODE_AUDIT_10 §8.1.
    private func resolvedModel(for row: ItemRowModel, rootManager: RootManager) -> (any ModelType)? {
        rootManager.itemRootController(for: row.typeId)?.itemControllable.itemSync(for: row.itemId)
    }
}

private struct SheetSecondaryRowView: View {
    let rootModel: SheetRootModel
    let sheetModel: SheetModel
    let shareResult: ShareValueResult

    var body: some View {
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
}

private struct SheetEntryRowsView<LinkType: LinkDataTransferable>: View {
    let rootModel: SheetRootModel
    let sheetModel: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    let focusedEntryId: FocusState<UUID?>.Binding
    @Binding var dropTargetEntryId: UUID?

    var body: some View {
        ForEach(sheetModel.entries) { entry in
            if !entry.isHidden {
                row(entry: entry)
                    .transition(.persistedSheetEntry)
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

    @ViewBuilder private func row(entry: SheetModel) -> some View {
        SheetEntryView(rootModel: rootModel, parentModel: sheetModel, entryModel: entry, isEditor: isEditor, linkTypes: linkTypes, focusedEntryId: focusedEntryId)
            .frame(maxWidth: .infinity, alignment: .leading)
#if !os(tvOS)
            // Also gated off while the entry editor's own drop-link header overlay is showing —
            // see `SheetEditorModel.isEntryEditorPresented`. Disabling the row's `.dropDestination`
            // at the source (rather than leaning on `.allowsHitTesting(false)` upstream) keeps this
            // correct on macOS 26.6 and iOS 26/27, where a covered row still steals the drop.
            .applyIf(isEditor && !rootModel.editorModel.isEntryEditorPresented) {
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
                SheetView(root: root, rootModel: rootModel, sheetModel: subEntry, isEditor: isEditor, linkTypes: linkTypes, focusedEntryId: focusedEntryId)
                    .padding(.leading, nestedSheetLeadingInset)
                    .transition(.persistedSheetEntry)
            }
        }
    }

    private func handleDrop(items: [LinkType], targetEntry: SheetModel) -> Bool {
        rootModel.handleDrop(items: items, targetEntry: targetEntry, parentModel: sheetModel)
    }
}

private struct SheetEndRowView: View {
    var body: some View {
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
    @Previewable @FocusState var focusedEntryId: UUID?
    let fixture = FakeItemRootControllerFixture()
    ScrollView {
        SheetView(
            root: fixture.root,
            rootModel: fixture.sheetRootModel,
            sheetModel: fixture.sheetRootModel.sheetModel,
            isEditor: true,
            linkTypes: EmptyLinkTransferable.self,
            focusedEntryId: $focusedEntryId
        )
        .padding()
    }
    .environment(AppGameStateModel())
}
