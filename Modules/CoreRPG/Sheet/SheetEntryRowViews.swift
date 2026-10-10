// @copyright André Trettin

import SwiftUI

// Split out of SheetEntryView.swift — see CODE_AUDIT_19 §9.23.

// MARK: - Extracted subviews (CODE_AUDIT §8.2)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` properties on `SheetEntryView` itself that all re-evaluated whenever any part
// of `SheetEntryView`'s body did.

/// Wraps the row's content in its outer `VStack`, choosing between review-placeholder
/// content and the ordinary before-inline/main-row/description/inline-editor/after-inline
/// arrangement.
struct SheetEntryRowContentView: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let isEditor: Bool
    let shareResult: ShareValueResult
    @Binding var isEditTypePickerPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entryModel.isReviewPlaceholder, let reviewModel = entryModel.entryReviewModel {
                SheetEntryReviewPlaceholderView(
                    entryModel: entryModel,
                    reviewModel: reviewModel
                )
            } else {
                SheetEntryBeforeInlineView(entryModel: entryModel, rootModel: rootModel)

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

                SheetEntryInlineEditorRowView(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, isEditor: isEditor)

                SheetEntryAfterInlineView(entryModel: entryModel, rootModel: rootModel)
            }

            if let reviewModel = entryModel.entryReviewModel, reviewModel.hasDifferences {
                SheetEntryReviewAlternativesView(reviewModel: reviewModel)
            }
        }
    }
}

/// Inline media shown before the main row: review snapshots when reviewing, otherwise the
/// resolved photo row viewer for photo entries.
struct SheetEntryBeforeInlineView: View {
    let entryModel: SheetModel
    let rootModel: SheetRootModel

    var body: some View {
        if entryModel.entryReviewModel != nil {
            ForEach(entryModel.inlineEntries) { inlineSheet in
                SheetEntryReviewInlineSnapshotView(sheetModel: inlineSheet)
            }
        } else {
            ForEach(entryModel.inlineEntries) { inlineSheet in
                switch inlineSheet.sheetType {
                case .photo:
                    // Use inlineSheet.source (the photo item) not entryModel.source (the parent entry)
                    // for viewer resolution. Whether this inline photo may show its own share button
                    // comes from `inlineSheet.isShareable`, which the containing module sets when it
                    // builds the inline sheet: MapRPG's `SheetController` sets it to false, because a
                    // photo embedded in a Map shares only through the Map itself. See CODE_AUDIT_19 §9.27.
                    SheetRowResolver.rowViewer(for: SheetRowResolver.viewController(for: inlineSheet.source, rootModel: rootModel), source: inlineSheet.source, destination: inlineSheet.destination, rootModel: rootModel, isShareable: inlineSheet.isShareable)
                        .frame(height: 96)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .clipShape(.rect(cornerRadius: 16))
                default:
                    EmptyView()
                }
            }
        }
    }
}

/// Inline media shown after the main row: resolved dice and pdf row viewers.
struct SheetEntryAfterInlineView: View {
    let entryModel: SheetModel
    let rootModel: SheetRootModel

    var body: some View {
        if entryModel.entryReviewModel == nil {
            ForEach(entryModel.inlineEntries) { inlineSheet in
                switch inlineSheet.sheetType {
                case .dice:
                    // Use inlineSheet.source for both viewController lookup and rowViewer
                    SheetRowResolver.rowViewer(
                        for: SheetRowResolver.viewController(for: inlineSheet.destination.typeId == .value ? inlineSheet.destination : inlineSheet.source, rootModel: rootModel),
                        source: inlineSheet.source,
                        destination: inlineSheet.destination,
                        rootModel: rootModel
                    )
                case .pdf:
                    // Use inlineSheet.source for both viewController lookup and rowViewer
                    SheetRowResolver.rowViewer(for: SheetRowResolver.viewController(for: inlineSheet.source, rootModel: rootModel), source: inlineSheet.source, destination: inlineSheet.destination, rootModel: rootModel)
                default:
                    EmptyView()
                }
            }
        }
    }
}

/// The inline value quick-editor shown in viewer mode while `entryModel.isEditing`.
struct SheetEntryInlineEditorRowView: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let isEditor: Bool

    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel

    var body: some View {
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
}

/// The row's primary content: name/preview viewer, edit/delete/take-over/AI-assist buttons.
struct SheetEntryMainRowView: View {
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

            if !entryModel.isGeneratedAnswer && (isEditor || (entryModel.editType != .none && rootModel.offersInlineEditing)) && (entryModel.sheetType == .item || entryModel.sheetType == .group) {
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
                            .imageScale(.large)
                    }
                    .padding(8)
                    .minimumHitArea()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
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
                    SheetRowResolver.rowViewer(for: SheetRowResolver.viewController(for: entryModel.source, rootModel: rootModel), source: entryModel.source, destination: entryModel.destination, rootModel: rootModel)
                case .photo:
                    SheetRowResolver.rowViewer(for: SheetRowResolver.viewController(for: entryModel.source, rootModel: rootModel), source: entryModel.source, destination: entryModel.destination, rootModel: rootModel)
                        .frame(height: 256)
                        .clipShape(.rect(cornerRadius: 16))
                case .pdf, .space, .weather:
                    SheetRowResolver.rowViewer(for: SheetRowResolver.viewController(for: entryModel.source, rootModel: rootModel), source: entryModel.source, destination: entryModel.destination, rootModel: rootModel)
                        .frame(height: 256)

                case .audio:
                    HStack {
                        SheetRowResolver.rowViewer(for: SheetRowResolver.viewController(for: entryModel.source, rootModel: rootModel), source: entryModel.source, destination: entryModel.destination, rootModel: rootModel)
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
struct SheetEntryContentRowView: View {
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
struct SheetEntryEditTypeIndicatorView: View {
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
                .padding(4)
                .background {
                    Circle().stroke(
                        theme.tint(for: entryModel.source.typeId).opacity(0.3)
                    )
                }
                // Enlarges the tap target to 44×44 pt without growing the row or
                // stretching the stroked circle — see CODE_AUDIT_Sheet §8.2. Lives on
                // the label so it's the shape the button itself hit-tests with.
                .minimumHitArea()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .imageScale(.small)
            .foregroundStyle(.foreground, .tint)
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
struct SheetEntryGeneratedSelectionBorder: View, Equatable {
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
struct SheetEntrySelectionBorder: View, Equatable {
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
