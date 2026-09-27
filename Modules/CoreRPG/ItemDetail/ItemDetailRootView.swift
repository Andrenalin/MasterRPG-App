// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Supporting Types

struct EditingItem: Identifiable {
    let id: UUID
    let model: any ItemDataAccessible

    init(_ model: any ItemDataAccessible) {
        self.id = model.id
        self.model = model
    }
}

/// Configuration for `ItemDetailRootView` behavior. A top-level type rather
/// than nested inside `ItemDetailRootView` — it doesn't depend on any of
/// that view's generic parameters, and nesting it would force every
/// external reference to spell out all of them (`Editor`, `LinkTypes`, and
/// `BottomOverlayBar` once that was added for CODE_AUDIT_10 §9.11) just to
/// name this type.
public struct ItemDetailConfiguration {
    public var editorAsBackground: Bool
    /// When `editorAsBackground` is true, layers the editor above the
    /// file-importer/description overlays instead of beneath them, padded
    /// clear of the top overlay. See `ItemEditorBackgroundView`.
    public var editorOnTop: Bool
    public var disableHideHeader: Bool
    public var isSubFolder: Bool

    public init(
        editorAsBackground: Bool = false,
        editorOnTop: Bool = false,
        disableHideHeader: Bool = false,
        isSubFolder: Bool = false
    ) {
        self.editorAsBackground = editorAsBackground
        self.editorOnTop = editorOnTop
        self.disableHideHeader = disableHideHeader
        self.isSubFolder = isSubFolder
    }
}

// MARK: - Main View

public struct ItemDetailRootView<Editor: View, LinkTypes: LinkDataTransferable, BottomOverlayBar: View>: View {
    public typealias Configuration = ItemDetailConfiguration

    public init(
        root: any ItemRootControllable,
        detailListController: FolderListControllable,
        selectedModel: any ItemDataAccessible,
        configuration: Configuration = Configuration(),
        linkTypes: LinkTypes.Type,
        showsBottomOverlayBar: Bool = true,
        bottomOverlayBarHeight: CGFloat? = nil,
        @ViewBuilder bottomOverlayBar: @escaping () -> BottomOverlayBar = { EmptyView() },
        @ViewBuilder editor: () -> Editor
    ) {
        self.root = root
        self.folderListController = detailListController
        self.selectedModel = selectedModel
        self.configuration = configuration
        self.showsBottomOverlayBar = showsBottomOverlayBar
        self.bottomOverlayBarHeight = bottomOverlayBarHeight
        self.bottomOverlayBar = bottomOverlayBar
        self.editor = editor()
    }

    let root: any ItemRootControllable
    let folderListController: FolderListControllable
    let selectedModel: any ItemDataAccessible
    let configuration: Configuration
    /// See `bottomOverlayBar`'s own doc — three modules (Audio/Weather/Dice)
    /// used to hand-implement this exact `safeAreaInset`/`overlay` stack
    /// independently. See CODE_AUDIT_10 §9.11.
    let showsBottomOverlayBar: Bool
    /// `nil` (the default) measures `bottomOverlayBar()`'s own real content,
    /// at zero opacity, for the safe-area inset — matching what
    /// Weather/Dice's bespoke copies did. A fixed value instead uses an
    /// invisible `Color.clear` spacer of that height, leaving
    /// `bottomOverlayBar()` to be composed however the caller wants for the
    /// *visible* copy only — matching Audio's bespoke copy, which reserves a
    /// fixed 80pt rather than measuring `AudioPlayerBarView` itself.
    let bottomOverlayBarHeight: CGFloat?
    /// A bar shown at `.bottom`, sitting between the editor content and
    /// `.openFileWindowOverlay` in the modifier chain so the file viewer
    /// still renders above it — callers apply their own padding/hit-testing
    /// modifiers inside this closure exactly as they want the *visible* bar
    /// to appear; only the invisible measurement copy (when
    /// `bottomOverlayBarHeight` is nil) is forced to zero opacity /
    /// disabled hit-testing / hidden accessibility here.
    let bottomOverlayBar: () -> BottomOverlayBar
    let editor: Editor

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var editingItem: EditingItem?
    @State private var itemIdHasUrl = UUID()
    @State private var headerModel = HeaderScrollModel()

    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        let content = ItemDetailContentView<Editor, LinkTypes>(
            root: root,
            model: selectedModel,
            configuration: configuration,
            editor: editor,
            headerModel: headerModel,
            folderListController: folderListController,
            editingItem: $editingItem
        )
        .moduleTint(root.configurable.module)
        .onChange(of: selectedModel.id, initial: true) {
            handleModelIdChange()
        }
        .onChange(of: selectedModel.url) { oldValue, _ in
            handleModelUrlChange(oldValue: oldValue)
        }
        .onChange(of: root.navigationModel.openHeaderEditor, initial: true) {
            guard root.navigationModel.openHeaderEditor else { return }
            root.navigationModel.openHeaderEditor = false
            openEditingSheet()
        }
        .onChange(of: folderListController.listModel.detailListModel?.subFolderRoute) {
            guard let itemId = folderListController.listModel.detailListModel?.subFolderRoute else { return }
            if appSizeModel.mode == .compact {
                navigator.navigate(to: folderListController.folderDestination(for: itemId))
                folderListController.listModel.detailListModel?.subFolderRoute = nil
            }
        }
        .onDisappear {
            clearCompactSelectionAfterPop()
        }

        // Three modules (Audio/Weather/Dice) used to hand-implement this
        // exact safeAreaInset/overlay stack independently, each with an
        // identical comment explaining why it bypasses the shared
        // `DetailFolderList` instead: the bar must sit *between* this
        // content and `.openFileWindowOverlay` (applied by the caller,
        // chained after this view) so the file viewer still renders above
        // it — wrapping the other way around would swap that stacking
        // order. See CODE_AUDIT_10 §9.11.
        // `BottomOverlayBar == EmptyView` means the caller never passed
        // `bottomOverlayBar:` at all (its default). Reaching `.safeAreaInset`
        // below with genuinely empty content collapses the *entire* detail
        // view — SwiftUI can't measure an `EmptyView`'s ideal size once
        // `.opacity(0)` erases it, and `HeaderContentScrollView`'s own
        // layout depends on that measurement. Regression from CODE_AUDIT_10
        // §9.11: every module without its own bar (the majority, via the
        // shared `DetailFolderList`) silently lost its detail editor.
        if BottomOverlayBar.self == EmptyView.self {
            content
        } else if showsBottomOverlayBar, let bottomOverlayBarHeight {
            content
                .safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
                    Color.clear
                        .frame(height: bottomOverlayBarHeight)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) { bottomOverlayBar() }
        } else if showsBottomOverlayBar {
            content
                .safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
                    bottomOverlayBar()
                        .opacity(0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .bottom) { bottomOverlayBar() }
        } else {
            content
        }
    }
}

// MARK: - Computed Properties

private extension ItemDetailRootView {
    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    var shouldShowContent: Bool {
        selectedModel.url != nil || fileTypes.isEmpty || selectedModel.specialCategory
    }
}

// MARK: - State Handlers

private extension ItemDetailRootView {
    func openEditingSheet() {
        withAnimation(accessibilityReduceMotion ? nil : .easeInOut) {
            editingItem = EditingItem(selectedModel) 
        }
    }
    
    func handleModelIdChange() {
        editingItem = nil
        folderListController.resetDetail(model: selectedModel)
        
        itemIdHasUrl = if selectedModel.url != nil {
            selectedModel.id
        } else if shouldShowContent {
            selectedModel.id
        } else {
            UUID()
        }
    }

    func handleModelUrlChange(oldValue: URL?) {
        guard oldValue == nil, itemIdHasUrl != selectedModel.id else { return }
        openEditingSheet()
    }

    func clearCompactSelectionAfterPop() {
        guard appSizeModel.mode == .compact, navigator.count == 0 else { return }
        let listModel = root.folderListControllable.listModel
        listModel.resetNavigationSelection()
        root.navigationModel.selectedItemId = nil
    }
}

// MARK: - Content View (Extracted)


// MARK: - Header View (Extracted)


// MARK: - File Importer View (Extracted & Unified)


// MARK: - Editor Foreground View (Extracted)


// MARK: - Editor Background View (Extracted)








#Preview("Item Detail Root Direct") {
    let fixture = FakeItemRootControllerFixture()
    ItemDetailRootView(
        root: fixture.root,
        detailListController: fixture.folderListController,
        selectedModel: FakeItemModel(
            id: .fixture1,
            name: "Ancient Map",
            category: .photo,
            description: "A weathered map showing the road to the lost keep.",
            tags: ["Map", "Quest"]
        ),
        linkTypes: EmptyLinkTransferable.self,
        editor: {
            Text(verbatim: "Editor content")
        }
    )
    .environment(AppWindowSizeModel())
}


// MARK: - Toolbar Content (Extracted)

struct ItemDetailToolbarContent: ToolbarContent {
    let root: any ItemRootControllable
    let model: any ItemDataAccessible
    let shouldShowContent: Bool
    let onEdit: () -> Void

    var body: some ToolbarContent {
        if !root.openFileWindowModel.showItem {
            ToolbarItem(placement: .primaryAction) {
                if shouldShowContent {
                    Button(action: onEdit) {
                        Label {
                            Text("Edit", bundle: .module)
                        } icon: {
                            Image(systemName: "pencil")
                        }
                        .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel(Text("Edit Item", bundle: .module))
                    .accessibilityHint(Text("Edit item details", bundle: .module))
                }
            }

            ToolbarItemGroup(placement: .secondaryActionAll) {
                MenuUndoRedoButton(root: root)
            }
        }
    }
}

// MARK: - View Extensions
