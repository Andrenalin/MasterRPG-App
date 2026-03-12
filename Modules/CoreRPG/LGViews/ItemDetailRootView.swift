// @copyright André Trettin

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

public struct ItemDetailRootView<Header: View, Editor: View, Inspector: View, Overlay: View, EntryEditor: View>: View {
    public init(detailListController: FolderListControllable, selectedModel: any ItemDataAccessable, editorAsBackground: Bool = false, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder inspector: () -> Inspector, @ViewBuilder entryEditor: () -> EntryEditor = EmptyView.init) where Overlay == EmptyView {
        self.detailListController = detailListController
        self.selectedModel = selectedModel
        self.editorAsBackground = editorAsBackground
        self.header = header()
        self.editor = editor()
        self.inspector = inspector()
        self.hasInspector = true
        self.overlay = { EmptyView() }()
        self.hasOverlay = false
        self.entryEditor = entryEditor()
    }
    
    public init(detailListController: FolderListControllable, selectedModel: any ItemDataAccessable, editorAsBackground: Bool = false, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder inspector: () -> Inspector, @ViewBuilder overlay: () -> Overlay, @ViewBuilder entryEditor: () -> EntryEditor = EmptyView.init) {
        self.detailListController = detailListController
        self.selectedModel = selectedModel
        self.editorAsBackground = editorAsBackground
        self.header = header()
        self.editor = editor()
        self.inspector = inspector()
        self.hasInspector = true
        self.overlay = overlay()
        self.hasOverlay = true
        self.entryEditor = entryEditor()
    }
    
    public init(detailListController: FolderListControllable, selectedModel: any ItemDataAccessable, editorAsBackground: Bool = false, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder overlay: () -> Overlay, @ViewBuilder entryEditor: () -> EntryEditor = EmptyView.init) where Inspector == EmptyView {
        self.detailListController = detailListController
        self.selectedModel = selectedModel
        self.editorAsBackground = editorAsBackground
        self.header = header()
        self.editor = editor()
        self.inspector = { EmptyView() }()
        self.hasInspector = false
        self.overlay = overlay()
        self.hasOverlay = true
        self.entryEditor = entryEditor()
    }
    
    public init(detailListController: FolderListControllable, selectedModel: any ItemDataAccessable, editorAsBackground: Bool = false, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder entryEditor: () -> EntryEditor = EmptyView.init) where Inspector == EmptyView, Overlay == EmptyView {
        self.detailListController = detailListController
        self.selectedModel = selectedModel
        self.editorAsBackground = editorAsBackground
        self.header = header()
        self.editor = editor()
        self.inspector = { EmptyView() }()
        self.hasInspector = false
        self.overlay = { EmptyView() }()
        self.hasOverlay = false
        self.entryEditor = entryEditor()
    }
    
    let selectedModel: any ItemDataAccessable
    let editorAsBackground: Bool
    let header: Header
    let editor: Editor
    let inspector: Inspector?
    let overlay: Overlay
    let hasOverlay: Bool
    let hasInspector: Bool
    let entryEditor: EntryEditor
    
    @Environment(\.appSizeMode) private var appSizeMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator
    
    @Environment(ListDisplayModel.self) private var listDisplayModel
    @Environment(SearchModel.self) private var searchModel
    @Environment(OpenFileWindowModel.self) private var openFileWindowModel
    
    @Environment(ItemRootController.self) private var root
    @Environment(DetailInspectorModel.self) private var detailInspectorModel
        
    @State private var isEditing = false
    @State private var itemIdHasUrl = UUID()
    @State private var selection = GroupItemSelectionModel()
    
    @State private var detailListController: FolderListControllable
    @State private var headerFooterModel = HeaderFooterScrollModel()
    
    @Namespace private var editSheetNamespace
    
    public var body: some View {
        contentScrollView(model: selectedModel)
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
    }
}

private extension ItemDetailRootView {
    func currentModel(model: any ItemDataAccessable) -> any ItemDataAccessable {
        guard let itemId = selection.selectedItem else { return model }
        return root.itemControllable.itemOrEmpty(for: itemId)
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
        HeaderFooterContentScrollView(model: headerFooterModel) {
            headerView(model: model)
        } content: {
            contentView(model: model)
        } footer: {
            bottomView(model: model)
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
                    .safeAreaInset(edge: .bottom, spacing: -headerFooterModel.footerOffset) {
                        bottomView(model: model).opacity(0)
                    }
            }
        }
        .animation(.default, value: model.url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.id, initial: true) {
            detailListController.resetParentModel(model: model)
            detailInspectorModel.canShowInspector = canShowInspector(model: model)
            updateInspectorStates(model: model)
            // Note: Cannot use .equatable() here as inspectorView returns heterogeneous types
            // The view is already optimized by onChange(of: model.id) triggering only on ID changes
            detailInspectorModel.currentInspectorView = AnyView(inspectorView(model: model))
            withAnimation(.easeInOut) { selection.selectedItem = nil }
            guard model.url != nil else {
                itemIdHasUrl = hasFile(model: model) ? model.id : UUID()
                return
            }
            itemIdHasUrl = model.id
        }
        .onChange(of: openFileWindowModel.showItem) {
            updateInspectorStates(model: model)
        }
        .onChange(of: model.name, initial: true) {
            guard model.name.isEmpty && (hasFile(model: model) || model.specialCategory) else { return }
            withAnimation(.easeInOut) { isEditing = true }
        }
        .onChange(of: model.url) { oldValue, newValue in
            guard oldValue == nil else { return }
            guard itemIdHasUrl != model.id else { return }
            withAnimation(.easeInOut) { isEditing = true }
        }
#if !os(tvOS)
        .applyIf(model.category != .folder && !fileTypes.isEmpty) {
            $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: { updateFile(url: $0, model: model)} ))
        }
#endif
        .sheet(isPresented: $isEditing) {
            ItemHeaderEditorView(editControllable: root.editControllable, model: currentModel(model: model))
                .colorScheme(colorScheme)
                .preferredColorScheme(colorScheme)
                .presentationContentInteraction(.resizes)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
                .tint(root.configurable.module.tint)
                .accentColor(root.configurable.module.tint)
#if os(iOS)
                .navigationTransition(.zoom(sourceID: "edit", in: editSheetNamespace))
#endif
        }
        .modifier(OpenFileViewerViewModifier(model: currentModel(model: model), module: root.configurable.module))
        .toolbar {
            toolbarContent(model: model)
        }
        .environment(selection)
    }
    
    func updateInspectorStates(model: any ItemDataAccessable) {
        withAnimation(.easeInOut) {
            if detailInspectorModel.showInspector && openFileWindowModel.showItem {
                detailInspectorModel.showInspector = false
            }
        }
    }
    
    func headerView(model: any ItemDataAccessable) -> some View {
        ZStack(alignment: .bottom) {
            header
            
            ItemDetailOverlayView(model: currentModel(model: model))
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
    
    @ViewBuilder func bottomView(model: any ItemDataAccessable) -> some View {
        if hasFile(model: model) && model.specialCategory == false && root.viewControllable.goupViewType != .none {
            CarouselItemView(root: root, model: model, selection: selection) {
                if root.viewControllable.goupViewType == .item {
                    ItemGroupItemView(root: root, model: model)
                } else {
                    if let cacheControllable = root.cacheControllable {
                        GroupedPhotoView(cacheController: cacheControllable, itemControllable: root.itemControllable, model: model)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .environment(selection)
            .transition(.move(edge: .bottom))
        }
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
                ItemDetailOverlayView(model: model, fullHeader: false, onlyDescription: true)
                    .padding()
                
                ListRootView(root: root, listController: detailListController, parentModel: model)
            } else {
#if os(macOS)
                ScrollView {
                    formEditor(model: model)
                }
#else
                formEditor(model: model)
#endif
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
            Form {
                if model.description.isEmpty == false {
                    ItemDetailOverlayView(model: model, fullHeader: false, onlyDescription: true)
                }
                
                editor
                    .onChange(of: root.editControllable.editorModel.scrollEntryId) {
                        guard let scrollEntryId = root.editControllable.editorModel.scrollEntryId else { return }
                        scrollProxy.scrollTo(scrollEntryId, anchor: .bottom)
                        root.editControllable.editorModel.scrollEntryId = nil
                    }
            }
            .scrollClipDisabled(true)
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
    }
    
    func editorContentBackgroundView(model: any ItemDataAccessable) -> some View {
        editor
            .id(model.id)
            .overlay(alignment: .top) {
                Group {
#if os(visionOS)
                    overlayFileImporter(model: model)
#else
                    GlassEffectContainer {
                        overlayFileImporter(model: model)
                    }
#endif
                }
                .padding()
                .opacity(model.specialCategory ? 0 : 1)
            }
            .overlay(alignment: .bottom) {
                if model.description.isEmpty == false {
                    Group {
#if os(visionOS)
                        overlayDescription(model: model)
#else
                        GlassEffectContainer {
                            overlayDescription(model: model)
                        }
#endif
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
        ItemDetailOverlayView(model: model, fullHeader: false, onlyDescription: true, lines: 3)
            .padding(.horizontal, 8)
            .padding(6)
#if !os(visionOS)
            .glassEffect(.regular)
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
            .glassEffect(.regular.interactive())
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
    
    func canShowInspector(model: any ItemDataAccessable) -> Bool {
        valueFor(iOS: appSizeMode == .regular, macOS: true, tvOS: true, visionOS: false)
    }

    func hasAnyInspector(model: any ItemDataAccessable) -> Bool {
        (hasInspector || model.specialCategory) && canShowInspector(model: model)
    }

    @ViewBuilder func inspectorView(model: any ItemDataAccessable) -> some View {
        Group {
            if hasAnyInspector(model: model) {
                if model.specialCategory {
                    LinkItemRootView(root: root, type: .inspector)
                        .environment(root.itemSelectionModel)
                } else {
                    inspector
                }
            } else {
                ContentUnavailableView {
                    Label {
                        Text("No Inspector for this item", bundle: .module)
                    } icon: {
                        Image(systemName: "scope")
                    }
                }
            }
        }
    }
    
    @ToolbarContentBuilder
    private func toolbarContent(model: any ItemDataAccessable) -> some ToolbarContent {
        if openFileWindowModel.showItem == false {
            ToolbarItem(placement: .primaryAction) {
                if (hasFile(model: currentModel(model: model)) || currentModel(model: model).specialCategory) {
                    Button {
                        withAnimation(.easeInOut) { isEditing = true }
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
