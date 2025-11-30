// @copyright André Trettin

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

public struct ItemDetailRootView<Header: View, Editor: View, Inspector: View, Overlay: View, EntryEditor: View>: View {
    public init(detailListController: FolderListControllable, selectedId: UUID?, editorAsBackground: Bool = false, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder inspector: () -> Inspector, @ViewBuilder entryEditor: () -> EntryEditor = EmptyView.init) where Overlay == EmptyView {
        self.detailListController = detailListController
        self.selectedId = selectedId
        self.editorAsBackground = editorAsBackground
        self.header = header()
        self.editor = editor()
        self.inspector = inspector()
        self.hasInspector = true
        self.overlay = { EmptyView() }()
        self.hasOverlay = false
        self.entryEditor = entryEditor()
    }

    public init(detailListController: FolderListControllable, selectedId: UUID?, editorAsBackground: Bool = false, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder inspector: () -> Inspector, @ViewBuilder overlay: () -> Overlay, @ViewBuilder entryEditor: () -> EntryEditor = EmptyView.init) {
        self.detailListController = detailListController
        self.selectedId = selectedId
        self.editorAsBackground = editorAsBackground
        self.header = header()
        self.editor = editor()
        self.inspector = inspector()
        self.hasInspector = true
        self.overlay = overlay()
        self.hasOverlay = true
        self.entryEditor = entryEditor()
    }

    public init(detailListController: FolderListControllable, selectedId: UUID?, editorAsBackground: Bool = false, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder overlay: () -> Overlay, @ViewBuilder entryEditor: () -> EntryEditor = EmptyView.init) where Inspector == EmptyView {
        self.detailListController = detailListController
        self.selectedId = selectedId
        self.editorAsBackground = editorAsBackground
        self.header = header()
        self.editor = editor()
        self.inspector = { EmptyView() }()
        self.hasInspector = false
        self.overlay = overlay()
        self.hasOverlay = true
        self.entryEditor = entryEditor()
    }

    public init(detailListController: FolderListControllable, selectedId: UUID?, editorAsBackground: Bool = false, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder entryEditor: () -> EntryEditor = EmptyView.init) where Inspector == EmptyView, Overlay == EmptyView {
        self.detailListController = detailListController
        self.selectedId = selectedId
        self.editorAsBackground = editorAsBackground
        self.header = header()
        self.editor = editor()
        self.inspector = { EmptyView() }()
        self.hasInspector = false
        self.overlay = { EmptyView() }()
        self.hasOverlay = false
        self.entryEditor = entryEditor()
    }

    let selectedId: UUID?
    let editorAsBackground: Bool
    let header: Header
    let editor: Editor
    let inspector: Inspector?
    let overlay: Overlay
    let hasOverlay: Bool
    let hasInspector: Bool
    let entryEditor: EntryEditor
    
    @Environment(\.appSizeMode) private var appSizeMode
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
    
    public var body: some View {
        let _ = Self._printChanges()
        if let detailModel {
            contentScrollView(model: detailModel)
                .tint(root.module.tint)
                .accentColor(root.module.tint)
        }
    }
}

private extension ItemDetailRootView {
    var detailModel: (any ItemDataAccessable)? {
        guard let itemId = selectedId else { return nil }
        return root.itemControllable.itemSync(for: itemId)
    }
    
    func selectedModel(model: any ItemDataAccessable) -> any ItemDataAccessable {
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
        Text("\(Image(systemName: root.module.icon)) \(root.module.title)")
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
                .fill(root.module.color)
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
            detailInspectorModel.currentInspectorView = AnyView(inspectorView(model: model))
            withAnimation { selection.selectedItem = nil }
            guard model.url != nil else {
                itemIdHasUrl = hasFile(model: model) ? model.id : UUID()
                return
            }
            itemIdHasUrl = model.id
        }
        .onChange(of: model.name, initial: true) {
            guard model.name.isEmpty && (hasFile(model: model) || model.specialCategory) else { return }
            withAnimation { isEditing = true }
        }
        .onChange(of: model.url) { oldValue, newValue in
            guard oldValue == nil else { return }
            guard itemIdHasUrl != model.id else { return }
            withAnimation { isEditing = true }
        }
#if !os(tvOS)
        .applyIf(model.category != .folder && !fileTypes.isEmpty) {
            $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: { updateFile(url: $0, model: model)} ))
        }
#endif
        .sheet(isPresented: $isEditing) {
            ItemHeaderEditorView(editControllable: root.editControllable, model: selectedModel(model: model))
                .presentationContentInteraction(.resizes)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .tint(root.module.tint)
                .accentColor(root.module.tint)
        }
        .modifier(OpenFileViewerViewModifier(model: selectedModel(model: model), module: root.module))
        .toolbar {
            toolbarContent(model: model)
        }
        .environment(selection)
    }
    
    func headerView(model: any ItemDataAccessable) -> some View {
        ZStack(alignment: .bottom) {
            header
            
            ItemDetailOverlayView(model: selectedModel(model: model))
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
                FileImporterView(editControllable: root.editControllable, fileTypes: fileTypes, module: root.module)
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
        .opacity(hasFile(model: selectedModel(model: model)) || selectedModel(model: model).specialCategory ? 0 : 1)
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
            
            if selectedModel(model: model).specialCategory == false && editorAsBackground {
                editorContentBackgroundView(model: selectedModel(model: model))
            } else {
                editorContentView(model: selectedModel(model: model))
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
        Form {
            if model.description.isEmpty == false {
                ItemDetailOverlayView(model: model, fullHeader: false, onlyDescription: true)
            }
            
            editor
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
            .padding()
#if !os(visionOS)
            .glassEffect(.regular)
#endif
    }
    
    func overlayFileImporter(model: any ItemDataAccessable) -> some View {
        HStack {
            Text(model.url?.absoluteString ?? "No file is set")
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if root.viewControllable.fileImporterViewType == .file {
                FileImporterView(editControllable: root.editControllable, fileTypes: fileTypes, module: root.module)
            } else {
                root.viewControllable.fileImporterView(for: model.id, preopen: false, layoutDown: true)
            }
        }
        .padding()
#if !os(visionOS)
        .glassEffect(.regular.interactive())
#endif
    }
    
    func updateFile(url: URL, model: any ItemDataAccessable) {
        root.editControllable.resetFile(url: url, module: root.module)
    }
}

// MARK: - Inspector

private extension ItemDetailRootView {
    
    func canShowInspector(model: any ItemDataAccessable) -> Bool {
        let platform = valueFor(iOS: appSizeMode == .regular, macOS: true, tvOS: true, visionOS: false)
        return (hasInspector || model.specialCategory) && platform && openFileWindowModel.showItem == false
    }
    
    @ViewBuilder func inspectorView(model: any ItemDataAccessable) -> some View {
        if model.specialCategory {
            LinkItemRootView(root: root, type: .inspector)
        } else {
            inspector
        }
    }
        
    @ToolbarContentBuilder
    private func toolbarContent(model: any ItemDataAccessable) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if openFileWindowModel.showItem == false && (hasFile(model: selectedModel(model: model)) || selectedModel(model: model).specialCategory) {
                Button {
                    withAnimation { isEditing = true }
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        ToolbarItemGroup(placement: .secondaryActionAll) {
            MenuUndoRedoButton(root: root)
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
