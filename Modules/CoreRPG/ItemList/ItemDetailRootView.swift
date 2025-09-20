// @copyright André Trettin

import SwiftData
import SwiftUI
import UniformTypeIdentifiers


public struct ItemDetailRootView<Header: View, Editor: View, Inspector: View, Overlay: View, EntryEditor: View>: View {
    public init(selectedId: UUID?, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder inspector: () -> Inspector = EmptyView.init, @ViewBuilder entryEditor: () -> EntryEditor = EmptyView.init) where Overlay == EmptyView {
        self.selectedId = selectedId
        self.header = header()
        self.editor = editor()
        self.inspector = inspector()
        self.overlay = { EmptyView() }()
        self.hasOverlay = false
        self.entryEditor = entryEditor()
    }

    public init(selectedId: UUID?, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder inspector: () -> Inspector = EmptyView.init, @ViewBuilder overlay: () -> Overlay, @ViewBuilder entryEditor: () -> EntryEditor = EmptyView.init) {
        self.selectedId = selectedId
        self.header = header()
        self.editor = editor()
        self.inspector = inspector()
        self.overlay = overlay()
        self.hasOverlay = true
        self.entryEditor = entryEditor()
    }

    let selectedId: UUID?
    let header: Header
    let editor: Editor
    let inspector: Inspector
    let overlay: Overlay
    let hasOverlay: Bool
    let entryEditor: EntryEditor
    
    @Environment(\.modelContext) private var modelContext
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @Environment(ListDisplayModel.self) private var listDisplayModel
    @Environment(SearchModel.self) private var searchModel
    @Environment(OpenFileWindowModel.self) private var openFileWindowModel

    @Environment(ItemRootController.self) private var root
    
    @State private var cacheItemListModel = CacheItemListModel()
    @State private var isEditing = false
    @State private var itemIdHasUrl = UUID()
    @State private var selection = GroupItemSelectionModel()
    @State private var showInspector = false

    public var body: some View {
        //let _ = Self._printChanges()
        if let selectedModel {
            contentScrollView(model: selectedModel)
        }
    }
}

private extension ItemDetailRootView {
    var selectedModel: ItemDataModel? {
        if let selectedId {
            return ItemDataModel.model(modelContext: modelContext, id: selectedId)
        } else {
            return root.listControllable.listModel.selectedModel
        }
    }
 
    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    func hasFile(model: ItemDataModel) -> Bool {
        model.url != nil || fileTypes.isEmpty
    }
    
    var navigationHeader: Text {
        Text("\(Image(systemName: root.module.icon)) \(root.module.title)")
    }
    
    @ViewBuilder func contentScrollView(model: ItemDataModel) -> some View {
        HeaderFooterContentScrollView {
            headerView(model: model)
        } content: {
            contentView(model: model)
        } footer: {
            bottomView(model: model)
        } background: {
            Rectangle()
                .fill(model.module.color)
        }
        .overlay(alignment: .center) {
            entryEditor
        }
        .overlay(alignment: .bottom) {
            if hasOverlay {
                overlay
                    .safeAreaInset(edge: .bottom) {
                        bottomView(model: model).opacity(0)
                    }
            }
        }
        .animation(.default, value: model.url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.id, initial: true) {
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
#if !os(visionOS)
        .inspector(isPresented: $showInspector) {
#if os(iOS)
            if horizontalSizeClass == .regular {
                inspectorView(model: model)
            }
#else
            inspectorView(model: model)
#endif
        }
#endif
        .sheet(isPresented: $isEditing) {
            ItemHeaderEditorView(editControllable: root.editControllable, model: model)
                .presentationContentInteraction(.resizes)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .tint(root.module.tint)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if openFileWindowModel.showItem == false && (hasFile(model: model) || model.specialCategory) {
                    Button {
                        withAnimation { isEditing = true }
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                inspectorButton()
            }
        }
        .modifier(OpenFileViewerViewModifier(model: model, module: root.module, toolbarSecondaryButton: EmptyView.init))
        .environment(selection)
    }
    
    func headerView(model: ItemDataModel) -> some View {
        ZStack(alignment: .bottom) {
            header
            
            ItemDetailOverlayView(model: model)
                .padding()
        }
        .overlay(alignment: .top) {
            navigationHeader.font(.title)
                .padding(.top, -64)
        }
    }
    
    var canShowInspector: Bool {
#if os(iOS)
        horizontalSizeClass == .regular
#else
        true
#endif
    }
    
    @ViewBuilder func initialFileImporterView(model: ItemDataModel) -> some View {
        HStack {
            FileImporterView(editControllable: root.editControllable, model: model, fileTypes: fileTypes)
                .padding(32)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.tint, lineWidth: 2)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(hasFile(model: model) || model.specialCategory ? 0 : 1)
        .transition(.scale)
    }
    
    @ViewBuilder func bottomView(model: ItemDataModel) -> some View {
        if hasFile(model: model) && model.specialCategory == false && root.viewControllable.goupViewType != .none {
            CarouselItemView(root: root, model: model, selection: selection) {
                if root.viewControllable.goupViewType == .item {
                    ItemGroupItemView(model: model)
                } else {
                    if let cacheControllable = root.cacheControllable {
                        GroupedPhotoView(cacheController: cacheControllable, model: model)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .environment(selection)
            .transition(.move(edge: .bottom))
        }
    }
    
    @ViewBuilder func contentView(model: ItemDataModel) -> some View {
        ZStack {
            initialFileImporterView(model: model)
            
#if os(macOS)
            ScrollView {
                editorContentView(model: model)
            }
#else
            editorContentView(model: model)
#endif
        }
    }
    
    func editorContentView(model: ItemDataModel) -> some View {
        Group {
            if model.specialCategory {
                ItemDetailOverlayView(model: model, fullHeader: false, onlyDescription: true)
                    .padding()
                
                ListRootView(root: root, parentModel: model)
            } else {
                Form {
                    if model.information.isEmpty == false {
                        ItemDetailOverlayView(model: model, fullHeader: false, onlyDescription: true)
                    }

                    editor
                }
                .scrollBounceBehavior(.basedOnSize)
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
    
    @ViewBuilder func inspectorView(model: ItemDataModel) -> some View {
        if model.specialCategory {
            LinkRootView(root: root, type: .inspector)
        } else {
            inspector
        }
    }
    
    func updateFile(url: URL, model: ItemDataModel) {
        root.editControllable.resetFile(url: url, in: model)
    }
    
    @ViewBuilder func inspectorButton() -> some View {
        ControlGroup {
            if canShowInspector && openFileWindowModel.showItem == false {
                Button {
                    withAnimation { showInspector.toggle() }
                } label: {
                    Image(systemName: "scope")
                }
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
