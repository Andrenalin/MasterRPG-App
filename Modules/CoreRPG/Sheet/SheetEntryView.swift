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
                rowContent
            } else {
                // A `Button` wrapping the row content directly, not an invisible
                // `.background()` button behind it — a background button never reliably
                // received taps inside the containing ScrollView/LazyVStack (confirmed
                // live on-device; same root cause fixed for `ListRowItemView`). Nested
                // interactive elements (link buttons in `LinkHighlightTextView`, edit/
                // delete/take-over buttons) keep working independently — SwiftUI resolves
                // a tap to whichever button is topmost/most specific at that point.
                Button(action: performPrimaryAction) {
                    rowContent
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

/// Shared by every extracted subview below that needs to resolve a viewer for a row's source
/// — kept file-scoped rather than promoted onto `SheetRootModel` to keep this decomposition
/// self-contained. See CODE_AUDIT §8.2.
@MainActor
private func resolvedViewController(for source: ItemRowModel, rootModel: SheetRootModel) -> ViewControllable? {
    rootModel.rootManager.rootModel(for: source.typeId)?.viewControllable
}

/// Mirrors `resolvedViewController` above: resolves `row`'s model once
/// here, at this per-row (but not per-item-in-a-list) boundary, instead of
/// letting `rowViewer`'s leaf re-resolve via `itemSync`/`itemOrEmpty` deep
/// inside its own `body` — that subscribes the leaf to the *entire*
/// `itemData` dictionary (Observation tracks a dictionary property at
/// whole-property granularity), so any item edit in the module
/// re-invalidates every other open row, not just this one. See
/// CODE_AUDIT_10 §8.1.
@MainActor
private func resolvedModel(for row: ItemRowModel, rootModel: SheetRootModel) -> (any ModelType)? {
    rootModel.rootManager.itemRootController(for: row.typeId)?.itemControllable.itemSync(for: row.itemId)
}

/// Shared by `SheetEntryView` and `SheetEntryMainRowView` below — resolves
/// `source`/`destination`'s models once here instead of leaving it to
/// `rowViewer`'s leaf to re-resolve via `itemSync`/`itemOrEmpty` inside its
/// own `body`. See `resolvedModel`'s doc comment / CODE_AUDIT_10 §8.1.
@MainActor
private func resolvedRowViewer(
    for viewController: ViewControllable?,
    source: ItemRowModel,
    destination: ItemRowModel,
    rootModel: SheetRootModel
) -> AnyView? {
    viewController?.rowViewer(
        source: source,
        destination: destination,
        sourceModel: resolvedModel(for: source, rootModel: rootModel),
        destinationModel: resolvedModel(for: destination, rootModel: rootModel)
    )
}

private extension SheetEntryView {
    func viewController(for source: ItemRowModel) -> ViewControllable? {
        resolvedViewController(for: source, rootModel: rootModel)
    }

    func rowViewer(viewController: ViewControllable?, source: ItemRowModel, destination: ItemRowModel) -> AnyView? {
        resolvedRowViewer(for: viewController, source: source, destination: destination, rootModel: rootModel)
    }

    @ViewBuilder var rowContent: some View {
        VStack(alignment: .leading) {
            if entryModel.isReviewPlaceholder, let reviewModel = entryModel.entryReviewModel {
                SheetEntryReviewPlaceholderView(
                    entryModel: entryModel,
                    reviewModel: reviewModel
                )
            } else {
                beforeInline

                SheetEntryMainRowView(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, isEditor: isEditor, shareResult: shareResult)

                SheetEntryContentRowView(
                    rootModel: rootModel,
                    parentModel: parentModel,
                    entryModel: entryModel,
                    isEditor: isEditor,
                    shareResult: shareResult,
                    isEditTypePickerPresented: $isEditTypePickerPresented
                )
                .allowsHitTesting(!entryModel.isGeneratedAnswer)

                inlineEditorRow

                afterInline
            }

            if let reviewModel = entryModel.entryReviewModel, reviewModel.hasDifferences {
                SheetEntryReviewAlternativesView(reviewModel: reviewModel)
            }
        }
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
                    rowViewer(viewController: viewController(for: inlineSheet.source), source: inlineSheet.source, destination: inlineSheet.destination)
                        .frame(height: 96)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .clipShape(.rect(cornerRadius: 16))
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
                    rowViewer(
                        viewController: viewController(for: inlineSheet.destination.typeId == .value ? inlineSheet.destination : inlineSheet.source),
                        source: inlineSheet.source,
                        destination: inlineSheet.destination
                    )
                case .pdf:
                    // Use inlineSheet.source for both viewController lookup and rowViewer
                    rowViewer(viewController: viewController(for: inlineSheet.source), source: inlineSheet.source, destination: inlineSheet.destination)
                default:
                    EmptyView()
                }
            }
        }
    }
    
    @ViewBuilder var inlineEditorRow: some View {
        if !isEditor && entryModel.isEditing && entryModel.editType != .none,
           let entryDataEditable = rootModel.entryDataEditable(for: entryModel.source) {
            // Observe the row's own state so the quick controls are inserted in the
            // same update as the edit-button tap on both iOS and macOS.
            InlineEditorView(entryDataEditable: entryDataEditable, updateHandler: { text in
                rootModel.updateSheetModel(entryModel: entryModel, parentModel: parentModel, updatedText: text)
                guard appGameStateModel.isGameRunning,
                      appGameStateModel.gameModus == .player,
                      let update = entryDataEditable.gameValueEntryUpdate(
                          itemId: entryModel.source.itemId,
                          entryId: entryModel.source.entryId
                      ) else {
                    return
                }
                networkActions?.game(update, .valueUpdate, nil)
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

// MARK: - Extracted subviews (CODE_AUDIT §8.2)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` properties on `SheetEntryView` itself that all re-evaluated whenever any part
// of `SheetEntryView`'s body did.

/// The row's primary content: name/preview viewer, edit/delete/take-over/AI-assist buttons.
private struct SheetEntryMainRowView: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let isEditor: Bool
    let shareResult: ShareValueResult

    var body: some View {
        HStack {
            if entryModel.isGeneratedAnswer {
                SheetEntryTakeOverButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: true)
            }

            if !entryModel.isGeneratedAnswer && (isEditor || entryModel.editType != .none) && (entryModel.sheetType == .item || entryModel.sheetType == .group) {
                SheetEntryEditButton(rootModel: rootModel, entryModel: entryModel, parentModel: parentModel, isEditor: isEditor, onlyIcon: true)
            }

            if !entryModel.isGeneratedAnswer, rootModel.isAIModeActive, canGoDeeper {
                Button {
                    rootModel.focusAISheetModel = entryModel
                } label: {
                    Label {
                        Text("Ask AI about this entry", bundle: .module)
                    } icon: {
                        Image(systemName: "questionmark.bubble")
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!hasDetailContent)
                .help(Text("Ask AI about this entry", bundle: .module))
            }

            Group {
                switch entryModel.sheetType {
                case .item, .group:
                    LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(entryModel.source.entryId ?? entryModel.source.itemId), text: entryModel.name, shareResults: shareResult))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.headline)

                case .dice:
                    resolvedRowViewer(for: resolvedViewController(for: entryModel.source, rootModel: rootModel), source: entryModel.source, destination: entryModel.destination, rootModel: rootModel)
                case .photo:
                    resolvedRowViewer(for: resolvedViewController(for: entryModel.source, rootModel: rootModel), source: entryModel.source, destination: entryModel.destination, rootModel: rootModel)
                        .frame(height: 256)
                        .clipShape(.rect(cornerRadius: 16))
                case .pdf, .space, .weather:
                    resolvedRowViewer(for: resolvedViewController(for: entryModel.source, rootModel: rootModel), source: entryModel.source, destination: entryModel.destination, rootModel: rootModel)
                        .frame(height: 256)

                case .audio:
                    HStack {
                        resolvedRowViewer(for: resolvedViewController(for: entryModel.source, rootModel: rootModel), source: entryModel.source, destination: entryModel.destination, rootModel: rootModel)
                        LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(entryModel.source.entryId ?? entryModel.source.itemId), text: audioDisplayText, shareResults: shareResult))
                    }
                    .font(.body)
                }
            }
            .allowsHitTesting(!entryModel.isGeneratedAnswer)

            if isEditor && (entryModel.isGeneratedAnswer || entryModel.sheetType == .item || entryModel.sheetType == .group) {
                SheetEntryDeleteButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: true)
            }

            if !entryModel.isGeneratedAnswer,
               let reviewModel = entryModel.entryReviewModel,
               reviewModel.hasDifferences {
                SheetEntryReviewButton(model: reviewModel)
            }
        }
    }

    private var audioDisplayText: String {
        if entryModel.description.isEmpty {
            entryModel.name
        } else if entryModel.name.isEmpty {
            entryModel.description
        } else {
            "**\(entryModel.name)**: \(entryModel.description)"
        }
    }

    private var canGoDeeper: Bool {
        entryModel.sheetType == .item || entryModel.sheetType == .group
    }

    private var hasDetailContent: Bool {
        !entryModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !entryModel.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The row's description text plus its leading edit-type indicator/picker.
private struct SheetEntryContentRowView: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let isEditor: Bool
    let shareResult: ShareValueResult
    @Binding var isEditTypePickerPresented: Bool

    var body: some View {
        if !entryModel.description.isEmpty {
            HStack {
                if entryModel.editType.isEditable {
                    SheetEntryEditTypeIndicatorView(
                        rootModel: rootModel,
                        parentModel: parentModel,
                        entryModel: entryModel,
                        isEditor: isEditor,
                        isPickerPresented: $isEditTypePickerPresented
                    )
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
}

/// The small edit-type glyph/picker shown beside a description row.
private struct SheetEntryEditTypeIndicatorView: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let isEditor: Bool
    @Binding var isPickerPresented: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        if isEditor, !supportedEditTypes.isEmpty {
            Button {
                isPickerPresented = true
            } label: {
                Label {
                    Text(entryModel.editType.localizedTitle)
                } icon: {
                    Image(systemName: entryModel.editType.icon)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .imageScale(.small)
            .foregroundStyle(.foreground, .tint)
            .padding(4)
            .background {
                Circle().stroke(
                    theme.tint(for: entryModel.source.typeId).opacity(0.3)
                )
            }
            // Matches SheetEntryMainRowView's "Ask AI about this entry" button — see
            // CODE_AUDIT_Sheet §8.2. Applied after `.background` so it enlarges the tap
            // target without stretching the stroked circle to fill it.
            .frame(minWidth: 44, minHeight: 44)
#if !os(tvOS)
            .popover(isPresented: $isPickerPresented, arrowEdge: .leading) {
                Picker(
                    selection: Binding(
                        get: { entryModel.editType },
                        set: { rootModel.updateEditType($0, for: entryModel, parent: parentModel) }
                    )
                ) {
                    ForEach(supportedEditTypes) { editType in
                        Label {
                            Text(editType.localizedTitle)
                        } icon: {
                            Image(systemName: editType.icon)
                        }
                        .tag(editType)
                    }
                } label: {
                    Text("Value Type", bundle: .module)
                }
                .pickerStyle(.inline)
                .padding()
                .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel(Text("Change Value Type", bundle: .module))
#endif
        } else {
            Image(systemName: entryModel.editType.icon)
                .imageScale(.small)
                .foregroundStyle(.foreground, .tint)
                .padding(4)
                .background {
                    Circle().stroke(
                        theme.tint(for: entryModel.source.typeId).opacity(0.3)
                    )
                }
                .accessibilityHidden(true)
        }
    }

    private var supportedEditTypes: [SheetModelEditType] {
        rootModel.supportedEditTypes(for: entryModel.source)
    }
}

/// The green "generated answer" glow border. No `@Environment` dependencies, so it's safe to
/// mark `Equatable` and skip re-rendering when neither flag changed. See CODE_AUDIT §8.4.
private struct SheetEntryGeneratedSelectionBorder: View, Equatable {
    let isGeneratedAnswer: Bool
    let isGeneratedSelected: Bool

    var body: some View {
        if isGeneratedAnswer {
            let green = Color.green
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(green.opacity(isGeneratedSelected ? 0.14 : 0.06))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [green, .mint.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isGeneratedSelected ? 3 : 2
                    )
            }
            .shadow(
                color: green.opacity(isGeneratedSelected ? 0.35 : 0.2),
                radius: isGeneratedSelected ? 6 : 4
            )
            .transition(.scale(scale: 0.98).combined(with: .opacity))
        }
    }
}

/// The tinted selection border. `tint` is resolved from `\.appTheme` by the caller (which
/// already re-renders on theme changes), so this leaf view itself has no `@Environment`
/// dependency and is safe to mark `Equatable`. See CODE_AUDIT §8.4.
private struct SheetEntrySelectionBorder: View, Equatable {
    let isSelected: Bool
    let tint: Color

    var body: some View {
        if isSelected {
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

#Preview("Sheet Entry Direct") {
    @Previewable @Namespace var namespace
    @Previewable @FocusState var focusedEntryId: UUID?
    SheetEntryView(
        rootModel: .fake,
        parentModel: .empty,
        entryModel: SheetRootModel.fake.sheetModel,
        isEditor: false,
        linkTypes: EmptyLinkTransferable.self,
        focusedEntryId: $focusedEntryId
    )
    .environment(AppGameStateModel())
}
