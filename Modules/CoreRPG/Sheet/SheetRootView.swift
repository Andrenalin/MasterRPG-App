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

    @FocusState private var focusSheetEntry: Bool
    
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        SheetView(
            root: root,
            rootModel: rootModel,
            sheetModel: rootModel.sheetModel,
            isEditor: isEditor,
            linkTypes: linkTypes
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(rootModel.sheetModel.id)
        .focusedSceneValue(\.selectedSheetEntry, rootModel.selectedSheetEntryFocusValue)
#if !os(tvOS)
        // Makes the sheet a Tab stop so the user can jump here from the sidebar list.
        // onKeyPress bubbles from any focused descendant, so arrow keys work whether
        // focus is on this container or on a child button — and TextFields consume
        // arrow keys themselves, so editing is never interrupted.
        .focusable()
        .focused($focusSheetEntry)
        .onChange(of: root.navigationModel.navigationColumnFocus) {
            focusSheetEntry <=> root.navigationModel.navigationColumnFocus == .detail
        }
        .onChange(of: root.navigationModel.selectedEntryId) {
            if root.navigationModel.selectedEntryId != nil {
                root.navigationModel.navigationColumnFocus <=> .detail
            }
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
            return .handled
        }
        .onKeyPress(.leftArrow, phases: .down) { _ in
            rootModel.clearSelection()
            root.navigationModel.navigationColumnFocus <=> .list
            return .handled
        }
#endif
    }
}

#Preview {
    let fixture = FakeItemRootControllerFixture()
    SheetRootView(root: fixture.root, rootModel: fixture.sheetRootModel, linkTypes: EmptyLinkTransferable.self)
        .environment(AppGameStateModel())
}
