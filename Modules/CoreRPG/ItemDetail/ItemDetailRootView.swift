// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Supporting Types

struct EditingItem: Identifiable {
    let id: UUID
    let model: any ItemDataAccessable

    init(_ model: any ItemDataAccessable) {
        self.id = model.id
        self.model = model
    }
}

// MARK: - Main View

public struct ItemDetailRootView<Editor: View, LinkTypes: LinkDataTransferable>: View {

    /// Configuration for ItemDetailRootView behavior
    public struct Configuration {
        public var editorAsBackground: Bool
        public var disableHideHeader: Bool
        public var isSubFolder: Bool

        public init(
            editorAsBackground: Bool = false,
            disableHideHeader: Bool = false,
            isSubFolder: Bool = false
        ) {
            self.editorAsBackground = editorAsBackground
            self.disableHideHeader = disableHideHeader
            self.isSubFolder = isSubFolder
        }
    }

    public init(
        root: any ItemRootControllable,
        detailListController: FolderListControllable,
        selectedModel: any ItemDataAccessable,
        configuration: Configuration = Configuration(),
        linkTypes: LinkTypes.Type,
        @ViewBuilder editor: () -> Editor
    ) {
        self.root = root
        self.folderListController = detailListController
        self.selectedModel = selectedModel
        self.configuration = configuration
        self.editor = editor()
    }

    let root: any ItemRootControllable
    let folderListController: FolderListControllable
    let selectedModel: any ItemDataAccessable
    let configuration: Configuration
    let editor: Editor
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var editingItem: EditingItem?
    @State private var itemIdHasUrl = UUID()
    @State private var headerModel = HeaderScrollModel()
    @Namespace private var editSheetNamespace
    
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        ItemDetailContentView(
            root: root,
            model: selectedModel,
            configuration: configuration,
            editor: editor,
            headerModel: headerModel,
            folderListController: folderListController,
            editingItem: $editingItem,
            editSheetNamespace: editSheetNamespace
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
        .sheet(item: $editingItem) { item in
            ManagedPresentationView {
                editingSheet(model: item.model)
            }
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

// MARK: - Presentation Views

private extension ItemDetailRootView {
    func editingSheet(model: any ItemDataAccessable) -> some View {
        ItemHeaderEditorView(editControllable: root.editControllable, model: model)
            .colorScheme(colorScheme)
            .preferredColorScheme(colorScheme)
            .presentationContentInteraction(.resizes)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled)
            .moduleTint(root.configurable.module)
#if os(iOS)
            .navigationTransition(.zoom(sourceID: "edit", in: editSheetNamespace))
#endif
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
        linkTypes: EmptyLinkTransferable.self
    ) {
        Text(verbatim: "Editor content")
    }
    .environment(AppWindowSizeModel())
}


// MARK: - Toolbar Content (Extracted)

struct ItemDetailToolbarContent: ToolbarContent {
    let root: any ItemRootControllable
    let model: any ItemDataAccessable
    let shouldShowContent: Bool
    let editSheetNamespace: Namespace.ID
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
#if os(iOS)
            .matchedTransitionSource(id: "edit", in: editSheetNamespace)
#endif
            
            ToolbarItemGroup(placement: .secondaryActionAll) {
                MenuUndoRedoButton(root: root)
            }
        }
    }
}

// MARK: - View Extensions
