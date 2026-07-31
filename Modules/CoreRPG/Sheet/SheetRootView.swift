// @copyright André Trettin

import SwiftUI

/// Renders one recursively materialized RPG sheet.
///
/// `SheetRootView` is the presentation shell for a ``SheetRootModel``. It
/// renders the model's root ``SheetModel`` through `SheetView`, publishes the
/// selected row to focused commands, and handles keyboard selection outside
/// tvOS. Nested linked sheets are rendered recursively by `SheetView`.
///
/// The view has two base presentation modes:
///
/// - Viewer mode (`isEditor == false`) supports reading, link expansion,
///   selection, and value quick editing when an entry has an editable type.
/// - Editor mode (`isEditor == true`) adds entry creation, deletion, reordering,
///   drag and drop, edit controls, and focused menu commands.
///
/// Search, generated previews, and import review are orthogonal states layered
/// on top of these two modes. AI presentation belongs to the parent screen so
/// it is anchored to that screen rather than to the recursive sheet content.
/// See `Docu/SHEETS.md` for the full state and data-flow description.
public struct SheetRootView<LinkType: LinkDataTransferable>: View {
    public init(
        root: ItemRootController,
        rootModel: SheetRootModel,
        isEditor: Bool = false,
        linkTypes: LinkType.Type = LinkDiceData.self
    ) {
        self.root = root
        self.rootModel = rootModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }
    
    let root: ItemRootController
    let rootModel: SheetRootModel
    let isEditor: Bool
    let linkTypes: LinkType.Type

    @Environment(AppFocusModel.self) private var appFocusModel
    // Per-entry focus target — not a container-level bool. Mirrors `ListRootView`'s
    // `focusedRowId`: a single `.focusable()` container competes with each entry row's own
    // `Button` for the click/Tab target, which is exactly what let focus and selection drift
    // apart (a tap could select one entry while system focus landed — or stayed — elsewhere).
    @FocusState private var focusedEntryId: UUID?

    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        SheetView(
            root: root,
            rootModel: rootModel,
            sheetModel: rootModel.sheetModel,
            isEditor: isEditor,
            linkTypes: linkTypes,
            focusedEntryId: $focusedEntryId
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(rootModel.sheetModel.id)
        .focusedSceneValue(\.selectedSheetEntry, rootModel.selectedSheetEntryFocusValue)
#if !os(tvOS)
        // onKeyPress bubbles from whichever entry row is focused up through this ancestor, so
        // arrow keys work no matter which row (or nesting depth) currently holds focus — and
        // TextFields consume arrow keys themselves, so editing is never interrupted.
        .onChange(of: appFocusModel.navigationColumnFocus) {
            guard appFocusModel.navigationColumnFocus == .detail else {
                focusedEntryId = nil
                return
            }
            // Arriving with nothing selected (e.g. fresh from the list) selects and focuses
            // the first entry; arriving with an existing selection just focuses it in place.
            if rootModel.selectedEntryId == nil, let first = rootModel.firstSelectableEntry {
                rootModel.setSelected(first, parent: rootModel.sheetModel)
            }
            // Deferred: the target entry's Button may not exist in the hierarchy yet (e.g.
            // scrolled out of view in the enclosing ScrollView) — assigning @FocusState
            // synchronously in that case is silently dropped. One runloop tick gives layout
            // time to settle first.
            let target = rootModel.selectedEntryId
            Task { @MainActor in
                focusedEntryId = target
            }
        }
        // Keeps focusId and selectedId the same in both directions. Selection can change without
        // going through a focus change (up/down arrow, an external route); this half keeps focus
        // following it. The other half — focus changing without going through `setSelected`, e.g.
        // Tab-key navigation onto a row — is handled per-row in `SheetEntryView`, which already
        // knows its own correct parent for the `setSelected(_:parent:)` call.
        .onChange(of: rootModel.selectedEntryId) {
            guard rootModel.selectedEntryId != nil else { return }
            appFocusModel.navigationColumnFocus <=> .detail
            focusedEntryId <=> rootModel.selectedEntryId
        }
        .onKeyPress(.downArrow, phases: .down) { _ in
            rootModel.selectNextEntry()
            return .handled
        }
        .onKeyPress(.upArrow, phases: .down) { _ in
            rootModel.selectPreviousEntry()
            return .handled
        }
        .onKeyPress(.escape, phases: .down) { _ in
            guard rootModel.selectedEntryId != nil else { return .ignored }
            rootModel.clearSelection()
            focusedEntryId = nil
            return .handled
        }
        .onKeyPress(.leftArrow, phases: .down) { _ in
            rootModel.clearSelection()
            focusedEntryId = nil
            appFocusModel.navigationColumnFocus <=> .list
            return .handled
        }
#endif
    }
}

#Preview {
    let fixture = FakeItemRootControllerFixture()
    SheetRootView(root: fixture.root, rootModel: fixture.sheetRootModel, linkTypes: EmptyLinkTransferable.self)
        .environment(AppGameStateModel())
        .environment(AppFocusModel())
}
