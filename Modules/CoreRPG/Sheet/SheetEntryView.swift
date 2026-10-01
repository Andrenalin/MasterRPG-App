// @copyright André Trettin

import SwiftUI

struct SheetEntryView<LinkType: LinkDataTransferable>: View {
    init(
        rootModel: SheetRootModel,
        parentModel: SheetModel,
        entryModel: SheetModel,
        isEditor: Bool,
        linkTypes: LinkType.Type,
        focusedEntryId: FocusState<UUID?>.Binding
    ) {
        self.rootModel = rootModel
        self.parentModel = parentModel
        self.entryModel = entryModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
        self.focusedEntryId = focusedEntryId
    }

    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    let focusedEntryId: FocusState<UUID?>.Binding
    
    @Environment(\.networkActions) private var networkActions
    @Environment(\.appTheme) private var theme
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.itemGenerationAction) private var itemGenerationAction
    @State private var isEditTypePickerPresented = false

    var body: some View {
        Group {
            // Review placeholders have no tap-to-select behavior — same as before.
            if entryModel.isReviewPlaceholder {
                SheetEntryRowContentView(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, isEditor: isEditor, shareResult: shareResult, isEditTypePickerPresented: $isEditTypePickerPresented)
            } else {
                // A `Button` wrapping the row content directly, not an invisible
                // `.background()` button behind it — a background button never reliably
                // received taps inside the containing ScrollView/LazyVStack (confirmed
                // live on-device; same root cause fixed for `ListRowItemView`). Nested
                // interactive elements (link buttons in `LinkHighlightTextView`, edit/
                // delete/take-over buttons) keep working independently — SwiftUI resolves
                // a tap to whichever button is topmost/most specific at that point.
                Button(action: performPrimaryAction) {
                    SheetEntryRowContentView(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, isEditor: isEditor, shareResult: shareResult, isEditTypePickerPresented: $isEditTypePickerPresented)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focused(focusedEntryId, equals: entryModel.id)
                // Covers focus reaching this row without going through `performPrimaryAction()`
                // (e.g. Tab-key navigation onto it, or the keyboard-arrow sync in
                // SheetRootView) — keeps focusId and selectedId the same regardless of how
                // focus got here, using this row's own already-known `parentModel` for
                // `setSelected`. This is also the sole place that requests a scroll: only
                // genuine focus activation should move the scroll view — see
                // `SheetRootModel.setSelected`. The scroll request is unconditional on focus
                // arriving here (not folded into the `setSelected` guard below), since
                // arrow-key navigation already updates `selectedEntryId` before this focus
                // sync runs.
                .onChange(of: focusedEntryId.wrappedValue) {
                    guard focusedEntryId.wrappedValue == entryModel.id else { return }
                    rootModel.handleFocusActivation(entryModel: entryModel, parent: parentModel)
                }
                .accessibilityLabel(primaryActionAccessibilityLabel)
                .accessibilityValue(generatedSelectionAccessibilityValue)
            }
        }
        .id(entryModel.source.entryId ?? entryModel.source.itemId)
        .sheetBorderColor(level: parentModel.level)
        .overlay {
            ZStack {
                SheetEntryGeneratedSelectionBorder(isGeneratedAnswer: entryModel.isGeneratedAnswer, isGeneratedSelected: entryModel.isGeneratedSelected)
                    .equatable()
                SheetEntrySelectionBorder(isSelected: entryModel.isSelected, tint: theme.tint(for: entryModel.source.typeId))
                    .equatable()
            }
            .allowsHitTesting(false)
        }
        .zIndex(entryModel.isGeneratedAnswer ? 1 : 0)
        .animation(accessibilityReduceMotion ? nil : .smooth, value: entryModel.isGeneratedAnswer)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: entryModel.isGeneratedSelected)
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2), value: entryModel.isSelected)
        .onChange(of: entryModel.name) {
            rootModel.scheduleParentReconcile(parentModel)
        }
        .onChange(of: entryModel.description) {
            rootModel.scheduleParentReconcile(parentModel)
        }
        // The context menu carries structural edit actions (add/duplicate/move/
        // delete) — only available where edits actually persist: the standalone
        // editor, or a game view deliberately treated as an editor too (see
        // `SheetRootModel.isGameEditor`/`persistsEdits`). `isGeneratedAnswer`
        // stays as its own allowance for the AI-draft Take Over/Delete actions.
        .applyIf(!entryModel.isReviewPlaceholder && (entryModel.isGeneratedAnswer || rootModel.persistsEdits)) {
            $0.contextMenuAll {
                if entryModel.isGeneratedAnswer {
                    SheetEntryTakeOverButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: false)
                    Divider()
                    SheetEntryDeleteButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: false)
                } else {
                    SheetEntryEditButton(rootModel: rootModel, entryModel: entryModel, parentModel: parentModel, isEditor: isEditor, onlyIcon: false)
                    SheetContextMenuView(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, isEditor: isEditor)
                    SheetEntryDeleteButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: false)
                        .tint(.red)
                }
            }
        }
        .applyIf(entryModel.isGeneratedAnswer) {
            $0.accessibilityAction(named: Text("Take Over", bundle: .module)) {
                rootModel.commitAIEntry(entryModel, parent: parentModel)
            }
        }
    }
}

/// Resolves a viewer for a row's source, shared by `SheetEntryView` and the extracted row
/// subviews in SheetEntryRowViews.swift. A namespace, not free functions: these helpers are
/// internal to CoreRPG, and a global name for each polluted the module's namespace.
/// See CODE_AUDIT §8.2, CODE_AUDIT_20 §9.4.
@MainActor
enum SheetRowResolver {
    static func viewController(for source: ItemRowModel, rootModel: SheetRootModel) -> ViewControllable? {
        rootModel.rootManager.rootModel(for: source.typeId)?.viewControllable
    }

    /// Resolves `row`'s model once here, at this per-row (but not per-item-in-a-list)
    /// boundary, instead of letting `rowViewer`'s leaf re-resolve via `itemSync`/`itemOrEmpty`
    /// deep inside its own `body` — that subscribes the leaf to the *entire* `itemData`
    /// dictionary (Observation tracks a dictionary property at whole-property granularity), so
    /// any item edit in the module re-invalidates every other open row, not just this one.
    /// See CODE_AUDIT_10 §8.1.
    private static func model(for row: ItemRowModel, rootModel: SheetRootModel) -> (any ModelType)? {
        rootModel.rootManager.itemRootController(for: row.typeId)?.itemControllable.itemSync(for: row.itemId)
    }

    /// Resolves `source`/`destination`'s models once here instead of leaving it to
    /// `rowViewer`'s leaf to re-resolve via `itemSync`/`itemOrEmpty` inside its own `body`.
    /// See `model(for:rootModel:)` / CODE_AUDIT_10 §8.1.
    static func rowViewer(
        for viewController: ViewControllable?,
        source: ItemRowModel,
        destination: ItemRowModel,
        rootModel: SheetRootModel,
        isShareable: Bool = true
    ) -> AnyView? {
        viewController?.rowViewer(
            source: source,
            destination: destination,
            sourceModel: model(for: source, rootModel: rootModel),
            destinationModel: model(for: destination, rootModel: rootModel),
            isShareable: isShareable
        )
    }
}

private extension SheetEntryView {
    func rowColor(for level: Int) -> Color {
#if os(macOS) || os(visionOS)
        .clear
#else
        level.isMultiple(of: 2) ? (colorScheme == .dark ? .black : .white) : .secondary.opacity(0.3)
#endif
    }
    
    var shareResult: ShareValueResult {
        ShareValueResult(
            networkActions: networkActions,
            resultCategory: ResultCategory(
                id: entryModel.source.itemId,
                childId: entryModel.source.entryId,
                module: entryModel.source.typeId
            ),
            showGame: appGameStateModel.isGameRunning,
            gameModus: appGameStateModel.gameModus,
            generationAction: itemGenerationAction
        )
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
    @Previewable @FocusState var focusedEntryId: UUID?
    SheetEntryView(
        rootModel: .fake,
        parentModel: .empty,
        entryModel: SheetRootModel.fake.sheetModel,
        isEditor: true,
        linkTypes: EmptyLinkTransferable.self,
        focusedEntryId: $focusedEntryId
    )
    .environment(AppGameStateModel())
}
