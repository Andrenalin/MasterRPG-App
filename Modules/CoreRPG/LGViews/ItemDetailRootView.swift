// @copyright André Trettin

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct EditingItem: Identifiable {
    let id: UUID
    let model: any ItemDataAccessable

    init(_ model: any ItemDataAccessable) {
        self.id = model.id
        self.model = model
    }
}

public struct ItemDetailRootView<Header: View, Editor: View, Overlay: View, EntryEditor: View>: View {

    /// Configuration for ItemDetailRootView behavior
    public struct Configuration {
        public var editorAsBackground: Bool
        public var hasOverlay: Bool

        public init(editorAsBackground: Bool = false, hasOverlay: Bool = false) {
            self.editorAsBackground = editorAsBackground
            self.hasOverlay = hasOverlay
        }
    }

    public init(
        detailListController: FolderListControllable,
        selectedModel: any ItemDataAccessable,
        configuration: Configuration = Configuration(),
        @ViewBuilder header: () -> Header,
        @ViewBuilder editor: () -> Editor,
        @ViewBuilder overlay: () -> Overlay,
        @ViewBuilder entryEditor: () -> EntryEditor
    ) {
        self.detailListController = detailListController
        self.selectedModel = selectedModel
        self.editorAsBackground = configuration.editorAsBackground
        self.header = header()
        self.editor = editor()
        self.overlay = overlay()
        self.hasOverlay = configuration.hasOverlay
        self.entryEditor = entryEditor()
    }

    let selectedModel: any ItemDataAccessable
    let editorAsBackground: Bool
    let header: Header
    let editor: Editor
    let overlay: Overlay
    let hasOverlay: Bool
    let entryEditor: EntryEditor
    
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator

    @Environment(OpenFileWindowModel.self) private var openFileWindowModel

    @Environment(ItemRootController.self) private var root
        
    @State private var editingItem: EditingItem?
    @State private var itemIdHasUrl = UUID()
    @State private var selection = GroupItemSelectionModel()

    @State private var detailListController: FolderListControllable
    @State private var headerModel = HeaderScrollModel()
    
    @Namespace private var editSheetNamespace
    
    public var body: some View {
        let _ = Self._printChanges()
        contentScrollView(model: selectedModel)
            .tint(root.configurable.module.tint)
    }
}

private extension ItemDetailRootView {
    func currentModel(model: any ItemDataAccessable) -> any ItemDataAccessable {
        model
    }
    
    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    func hasFile(model: any ItemDataAccessable) -> Bool {
        model.url != nil || fileTypes.isEmpty
    }
    
    var navigationHeader: Text {
        Text("\(Image(systemName: root.configurable.module.icon)) \(root.configurable.module.title)")
    }
    
    @ViewBuilder func contentScrollView(model: any ItemDataAccessable) -> some View {
        let _ = print("📜 ItemDetailRootView.contentScrollView() for model: \(model.name) (id: \(model.id))")
        HeaderContentScrollView(model: headerModel) {
            headerView(model: model)
        } content: {
            contentView(model: model)
        } background: {
            Rectangle()
                .fill(root.configurable.module.color)
        }
        .overlay(alignment: .center) {
            entryEditor
        }
        .overlay(alignment: .bottom) {
            if hasOverlay {
                overlay
            }
        }
        .animation(.easeInOut, value: model.url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.id, initial: true) {
            handleModelIdChange(model: model)
        }
        .task(id: model.id) {
            await openEditorForNewItemIfNeeded(model: model)
        }
        .onChange(of: model.name) {
            handleModelNameChange(model: model)
        }
        .onChange(of: model.url) { oldValue, newValue in
            handleModelUrlChange(model: model, oldValue: oldValue)
        }
#if !os(tvOS)
        .applyIf(model.category != .folder && !fileTypes.isEmpty) {
            $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: { updateFile(url: $0, model: model)} ))
        }
#endif
        .sheet(item: $editingItem) { item in
            editingSheet(model: item.model)
        }
        .modifier(OpenFileViewerViewModifier(model: currentModel(model: model), module: root.configurable.module))
        .toolbar {
            toolbarContent(model: model)
        }
        .environment(selection)
    }
    
    func openEditorForNewItemIfNeeded(model: any ItemDataAccessable) async {
        // Yield once to let the view settle before checking model state
        await Task.yield()
        guard model.name.isEmpty && (hasFile(model: model) || model.specialCategory) else { return }
        withAnimation(.easeInOut) { editingItem = EditingItem(currentModel(model: model)) }
    }

    func handleModelIdChange(model: any ItemDataAccessable) {
        // Reset editing state when switching items
        editingItem = nil

        detailListController.resetParentModel(model: model)
        withAnimation(.easeInOut) { selection.selectedItem = nil }

        guard model.url != nil else {
            itemIdHasUrl = hasFile(model: model) ? model.id : UUID()
            return
        }
        itemIdHasUrl = model.id
    }

    func handleModelNameChange(model: any ItemDataAccessable) {
        guard model.name.isEmpty && (hasFile(model: model) || model.specialCategory) else { return }
        withAnimation(.easeInOut) { editingItem = EditingItem(currentModel(model: model)) }
    }

    func handleModelUrlChange(model: any ItemDataAccessable, oldValue: URL?) {
        guard oldValue == nil else { return }
        guard itemIdHasUrl != model.id else { return }
        withAnimation(.easeInOut) { editingItem = EditingItem(currentModel(model: model)) }
    }

    func editingSheet(model: any ItemDataAccessable) -> some View {
        ItemHeaderEditorView(editControllable: root.editControllable, model: model)
            .colorScheme(colorScheme)
            .preferredColorScheme(colorScheme)
            .presentationContentInteraction(.resizes)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled)
            .tint(root.configurable.module.tint)
#if os(iOS)
            .navigationTransition(.zoom(sourceID: "edit", in: editSheetNamespace))
#endif
    }
    
    func headerView(model: any ItemDataAccessable) -> some View {
        ZStack(alignment: .bottom) {
            header
            
            ItemDetailOverlayView(model: currentModel(model: model), listDisplayModel: detailListController.listDisplayModel)
                .padding()
        }
        .overlay(alignment: .top) {
            navigationHeader.font(.title)
                .padding(.top, -64)
        }
    }
    
    @ViewBuilder func initialFileImporterView(model: any ItemDataAccessable) -> some View {
        HStack {
            if root.viewControllable.fileImporterViewType == .file {
                FileImporterView(editControllable: root.editControllable, fileTypes: fileTypes, itemId: model.id)
                    .padding(32)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.tint, lineWidth: 2)
                    }
            } else {
                root.viewControllable.fileImporterView(for: model.id, preopen: true, layoutDown: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(hasFile(model: currentModel(model: model)) || currentModel(model: model).specialCategory ? 0 : 1)
        .transition(.scale)
    }
    
    
    @ViewBuilder func contentView(model: any ItemDataAccessable) -> some View {
        ZStack {
            initialFileImporterView(model: model)
            
            if currentModel(model: model).specialCategory == false && editorAsBackground {
                editorContentBackgroundView(model: currentModel(model: model))
            } else {
                editorContentView(model: currentModel(model: model))
            }
        }
    }
    
    func editorContentView(model: any ItemDataAccessable) -> some View {
        Group {
            if model.specialCategory {
                ItemDetailOverlayView(model: model, listDisplayModel: detailListController.listDisplayModel, fullHeader: false, onlyDescription: true)
                    .padding()
                
                ListRootView(root: root, listController: detailListController, parentModel: model)
                    .environment(detailListController.listDisplayModel)
            } else {
                formEditor(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(hasFile(model: model) || model.specialCategory ? 1 : 0)
        .transition(.scale)
        .applyIf(hasOverlay) {
            $0.safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
                overlay.opacity(0)
            }
        }
    }
    
    func formEditor(model: any ItemDataAccessable) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if model.description.isEmpty == false {
                        ItemDetailOverlayView(model: model, listDisplayModel: detailListController.listDisplayModel, fullHeader: false, onlyDescription: true)
                    }
                    
                    editor
                        .onChange(of: root.editControllable.sheetEditorModel.scrollEntryId) {
                            guard let scrollEntryId = root.editControllable.sheetEditorModel.scrollEntryId else { return }
                            scrollProxy.scrollTo(scrollEntryId, anchor: .center)
                            root.editControllable.sheetEditorModel.scrollEntryId = nil
                        }
                }
                .padding()
            }
            .scrollClipDisabled(true)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
    
    func editorContentBackgroundView(model: any ItemDataAccessable) -> some View {
        editor
            .id(model.id)
            .overlay(alignment: .top) {
                GlassEffectContainerAll {
                    overlayFileImporter(model: model)
                }
                .padding()
                .opacity(model.specialCategory ? 0 : 1)
            }
            .overlay(alignment: .bottom) {
                if model.description.isEmpty == false {
                    GlassEffectContainerAll {
                        overlayDescription(model: model)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .opacity(hasFile(model: model) || model.specialCategory ? 1 : 0)
            .transition(.scale)
            .applyIf(hasOverlay) {
                $0.safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
                    overlay.opacity(0)
                }
            }
    }
    
    func overlayDescription(model: any ItemDataAccessable) -> some View {
        ItemDetailOverlayView(model: model, listDisplayModel: detailListController.listDisplayModel, fullHeader: false, onlyDescription: true, lines: 3)
            .padding(.horizontal, 8)
            .padding(6)
#if !os(visionOS)
            .glassEffectAll(.regular)
#endif
    }

    func overlayFileImporter(model: any ItemDataAccessable) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack {
                Text(model.url?.path(percentEncoded: false) ?? String(localized: "No file is set", bundle: .module).localizedString)
                    .font(.callout)
            }
            .padding(6)
#if !os(visionOS)
            .glassEffectAll(.regular.interactive())
#endif
            
            Spacer(minLength: 20)
            
            HStack {
                if root.viewControllable.fileImporterViewType == .file {
                    FileImporterView(editControllable: root.editControllable, fileTypes: fileTypes, itemId: model.id)
                } else {
                    root.viewControllable.fileImporterView(for: model.id, preopen: false, layoutDown: true)
                }
            }
            .zIndex(5)
        }
    }
    
    func updateFile(url: URL, model: any ItemDataAccessable) {
        Task {
            await root.editControllable.resetFile(url: url, itemId: model.id)
        }
    }
}

// MARK: - Inspector

private extension ItemDetailRootView {
    @ToolbarContentBuilder
    private func toolbarContent(model: any ItemDataAccessable) -> some ToolbarContent {
        if openFileWindowModel.showItem == false {
            ToolbarItem(placement: .primaryAction) {
                if (hasFile(model: currentModel(model: model)) || currentModel(model: model).specialCategory) {
                    Button {
                        withAnimation(.easeInOut) { editingItem = EditingItem(currentModel(model: model)) }
                    } label: {
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

//#Preview("Folder", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    @Previewable @Query var models: [ItemDataModel]
//
//    ItemDetailRootView(model: models.first(where: { $0.id == MockData.folderId })!)
//}
//
//#Preview("Collection", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    @Previewable @Query var models: [ItemDataModel]
//
//    ItemDetailRootView(model: models.first(where: { $0.id == MockData.playlistId })!)
//}
//
//#Preview("Item", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    @Previewable @Query var models: [ItemDataModel]
//
//    ItemDetailRootView(model: models.first(where: { $0.id == MockData.previewId })!)
//}
