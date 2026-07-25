// @copyright André Trettin

import SwiftUI

/// Presentation options for ``SheetRootView``.
///
/// These options add presentation features; they do not change whether the
/// sheet is in viewer or editor mode. Editor mode is selected by the
/// `isEditor` argument passed to ``SheetRootView`` and must match the mode used
/// to create its ``SheetRootModel``.
public struct SheetRootViewConfiguration: Equatable, Sendable {
    public init(showsAIAssistant: Bool = false) {
        self.showsAIAssistant = showsAIAssistant
    }

    /// Whether the supplied AI assistant view is overlaid once at the bottom of the sheet.
    public var showsAIAssistant: Bool
}

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
/// Search, AI assistance, generated previews, and import review are orthogonal
/// states layered on top of these two modes. See `Docu/SHEETS.md` for the full
/// state and data-flow description.
public struct SheetRootView<
    LinkType: LinkDataTransferable,
    DetailContent: View,
    AIAssistantContent: View
>: View {
    public init(
        root: ItemRootController,
        rootModel: SheetRootModel,
        isEditor: Bool = false,
        linkTypes: LinkType.Type = LinkDiceData.self,
        detailAction: ((SheetModel) -> Void)? = nil
    ) where DetailContent == EmptyView, AIAssistantContent == EmptyView {
        self.init(
            root: root,
            rootModel: rootModel,
            isEditor: isEditor,
            linkTypes: linkTypes,
            configuration: .init(),
            detailAction: detailAction,
            detailContent: { _ in EmptyView() },
            aiAssistantContent: { EmptyView() }
        )
    }

    public init(
        root: ItemRootController,
        rootModel: SheetRootModel,
        isEditor: Bool = false,
        linkTypes: LinkType.Type = LinkDiceData.self,
        configuration: SheetRootViewConfiguration,
        detailAction: ((SheetModel) -> Void)? = nil,
        @ViewBuilder aiAssistantContent: @escaping () -> AIAssistantContent
    ) where DetailContent == EmptyView {
        self.init(
            root: root,
            rootModel: rootModel,
            isEditor: isEditor,
            linkTypes: linkTypes,
            configuration: configuration,
            detailAction: detailAction,
            detailContent: { _ in EmptyView() },
            aiAssistantContent: aiAssistantContent
        )
    }

    public init(
        root: ItemRootController,
        rootModel: SheetRootModel,
        isEditor: Bool = false,
        linkTypes: LinkType.Type = LinkDiceData.self,
        detailAction: ((SheetModel) -> Void)? = nil,
        @ViewBuilder detailContent: @escaping (SheetModel) -> DetailContent
    ) where AIAssistantContent == EmptyView {
        self.init(
            root: root,
            rootModel: rootModel,
            isEditor: isEditor,
            linkTypes: linkTypes,
            configuration: .init(),
            detailAction: detailAction,
            detailContent: detailContent,
            aiAssistantContent: { EmptyView() }
        )
    }

    public init(
        root: ItemRootController,
        rootModel: SheetRootModel,
        isEditor: Bool = false,
        linkTypes: LinkType.Type = LinkDiceData.self,
        configuration: SheetRootViewConfiguration,
        detailAction: ((SheetModel) -> Void)? = nil,
        @ViewBuilder detailContent: @escaping (SheetModel) -> DetailContent,
        @ViewBuilder aiAssistantContent: @escaping () -> AIAssistantContent
    ) {
        self.root = root
        self.rootModel = rootModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
        self.configuration = configuration
        self.detailAction = detailAction
        self.detailContent = detailContent
        self.aiAssistantContent = aiAssistantContent
    }
    
    let root: ItemRootController
    let rootModel: SheetRootModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    let configuration: SheetRootViewConfiguration
    let detailAction: ((SheetModel) -> Void)?
    let detailContent: (SheetModel) -> DetailContent
    let aiAssistantContent: () -> AIAssistantContent

    @Namespace private var generatedAcceptanceNamespace
    @Environment(\.navigationColumnFocus) private var navigationColumnFocus

    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        VStack(alignment: .leading, spacing: 4) {
            SheetView(
                root: root,
                rootModel: rootModel,
                sheetModel: rootModel.sheetModel,
                isEditor: isEditor,
                linkTypes: linkTypes,
                generatedAcceptanceNamespace: generatedAcceptanceNamespace,
                detailAction: detailAction,
                detailContent: detailContent
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(rootModel.sheetModel.id)
        .applyIf(configuration.showsAIAssistant) {
            $0.overlay(alignment: .bottomTrailing) {
                aiAssistantContent()
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
        .focusedSceneValue(\.selectedSheetEntry, rootModel.selectedSheetEntryFocusValue)
#if !os(tvOS)
        // Makes the sheet a Tab stop so the user can jump here from the sidebar list.
        // onKeyPress bubbles from any focused descendant, so arrow keys work whether
        // focus is on this container or on a child button — and TextFields consume
        // arrow keys themselves, so editing is never interrupted.
        .focusable()
        .navigationColumnFocused(navigationColumnFocus, equals: .detail)
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
            navigationColumnFocus?.wrappedValue = .list
            return .handled
        }
#endif
    }
}

#Preview {
    let fixture = FakeItemRootControllerFixture()
    SheetRootView(root: fixture.root, rootModel: fixture.sheetRootModel, linkTypes: EmptyLinkTransferable.self)
}
