// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ItemDetailEditorView<Header: View, Editor: View, Inspector: View, Overlay: View>: View {
    init(root: any ItemRootControllable, model: ItemDataModel, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder inspector: () -> Inspector = EmptyView.init, @ViewBuilder overlay: () -> Overlay = EmptyView.init) {
        self.root = root
        self.model = model
        self.cacheItemListModel = CacheItemListModel()
        self.header = header()
        self.editor = editor()
        self.inspector = inspector()
        self.overlay = overlay()
    }
    
    let root: any ItemRootControllable
    let model: ItemDataModel
    let cacheItemListModel: CacheItemListModel
    let header: Header
    let editor: Editor
    let inspector: Inspector
    let overlay: Overlay
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    @State private var isEditing = false
    @State private var showInspector = false
    @State private var itemIdHasUrl = UUID()
    
    @Environment(SearchModel.self) private var searchModel
    @Environment(GroupItemSelectionModel.self) private var selection
    @Environment(OpenFileWindowModel.self) private var openFileWindowModel
    
    public var body: some View {
        let _ = Self._printChanges()
        HeaderFooterContentScrollView {
            headerView
        } content: {
            contentView
        } footer: {
            bottomView
                .overlay(alignment: .top) {
                    overlay
                        .offset(y: -100)
                }
        } background: {
            Rectangle()
                .fill(model.module.color)
        }
        .animation(.default, value: model.url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.id, initial: true) {
            guard model.url != nil else {
                itemIdHasUrl = hasFile ? model.id : UUID()
                return
            }
            itemIdHasUrl = model.id
        }
        .onChange(of: model.name, initial: true) {
            guard model.name.isEmpty && (hasFile || model.specialCategory) else { return }
            withAnimation { isEditing = true }
        }
        .onChange(of: model.url) { oldValue, newValue in
            guard oldValue == nil else { return }
            guard itemIdHasUrl != model.id else { return }
            withAnimation { isEditing = true }
        }
#if !os(tvOS)
        .applyIf(model.category != .folder && !fileTypes.isEmpty) {
            $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: updateFile))
        }
#endif
#if !os(visionOS)
        .inspector(isPresented: $showInspector) {
#if os(iOS)
            if horizontalSizeClass == .regular {
                inspectorView
            }
#else
            inspectorView
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
                if openFileWindowModel.showItem == false && (hasFile || model.specialCategory) {
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
    }
}

private extension ItemDetailEditorView {
    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    var hasFile: Bool {
        model.url != nil || fileTypes.isEmpty
    }
    
    var navigationHeader: Text {
        Text("\(Image(systemName: root.module.icon)) \(root.module.title)")
    }
    
    var headerView: some View {
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
    
    @ViewBuilder
    var initialFileImporterView: some View {
        HStack {
            FileImporterView(editControllable: root.editControllable, model: model, fileTypes: fileTypes)
                .padding(32)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)                    
                        .stroke(.tint, lineWidth: 2)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(hasFile || model.specialCategory ? 0 : 1)
        .transition(.scale)
    }
    
    @ViewBuilder
    var bottomView: some View {
        if hasFile && model.specialCategory == false && root.viewControllable.goupViewType != .none {
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
    
    @ViewBuilder
    var contentView: some View {
        ZStack {
            initialFileImporterView
            
#if os(macOS)
            ScrollView {
                editorContentView
            }
#else
            editorContentView
#endif
        }
    }
    
    var editorContentView: some View {
        Group {
            if model.specialCategory {
                ItemDetailOverlayView(model: model, fullHeader: false, onlyDescription: true)
                    .padding()
                
                ListRootView(root: root, parentModel: model)
            } else {
                Form {
                    editor
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(hasFile || model.specialCategory ? 1 : 0)
        .transition(.scale)
        .safeAreaInset(edge: .bottom) {
            overlay
        }
    }
    
    @ViewBuilder
    var inspectorView: some View {
        if model.specialCategory {
            LinkRootView(root: root, type: .inspector)
        } else {
            inspector
        }
    }
    
    func updateFile(url: URL) {
        root.editControllable.resetFile(url: url, in: model)
    }
    
    @ViewBuilder
    func inspectorButton() -> some View {
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
//    NavigationStack {
//        DetailRootView(itemId: MockData.folderId)
//    }
//    .preferredColorScheme(.dark)
//}
