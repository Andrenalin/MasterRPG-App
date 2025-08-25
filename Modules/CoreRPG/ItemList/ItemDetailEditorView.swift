// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ItemDetailEditorView<Header: View, Editor: View, Inspector: View>: View {
    init(root: any ItemRootControllable, model: ItemDataModel, @ViewBuilder header: () -> Header = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder inspector: () -> Inspector = EmptyView.init) {
        self.root = root
        self.model = model
        self.cacheItemListModel = CacheItemListModel()
        self.header = header()
        self.editor = editor()
        self.inspector = inspector()
    }

    let root: any ItemRootControllable
    let model: ItemDataModel
    let cacheItemListModel: CacheItemListModel
    let header: Header
    let editor: Editor
    let inspector: Inspector

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

        ZStack(alignment: .top) {
            Color.clear
                        
            initialFileImporterView

            backgroundView

            VStack {
                contentView

                bottomView
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.default, value: model.url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.id, initial: true) {
            openFileWindowModel.itemId = model.id
            openFileWindowModel.url = model.url
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
        .onChange(of: selection.selectedItem) {
            openFileWindowModel.itemId = selection.selectedItem ?? model.id
        }
#if !os(tvOS)
        .applyIf(model.category != .folder && !fileTypes.isEmpty) {
            $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: updateFile))
        }
#endif
#if !os(visionOS)
        .inspector(isPresented: $showInspector) {
            if model.specialCategory {
                LinkRootView(root: root, isInspector: true)
            }
        }
#endif
        .sheet(isPresented: $isEditing) {
            ItemHeaderEditorView(editControllable: root.editControllable, model: model)
                .presentationContentInteraction(.resizes)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
                if canShowInspector {
                    Button {
                        withAnimation { showInspector.toggle() }
                    } label: {
                        Image(systemName: "scope")
                    }
                }
            }
        }
    }
}

private extension ItemDetailEditorView {
    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    var hasFile: Bool {
        model.url != nil || fileTypes.isEmpty
    }

    var backgroundView: some View {
        VStack {
            header
        }
        .frame(height: 120)
        .background {
            //ConcentricRectangle()
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 32, bottomTrailingRadius: 32, topTrailingRadius: 0, style: .continuous)
                .fill(model.module.color.gradient)
                .ignoresSafeArea(edges: .top)
                .backgroundExtensionEffect()
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
                        .stroke(Color.accentColor, lineWidth: 2)
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
            .padding(.top, 2)
            .environment(selection)
            .transition(.move(edge: .bottom))
        }
    }

    @ViewBuilder
    var contentView: some View {
        VStack(spacing: 8) {
            ItemDetailOverlayView(model: model)

            if model.specialCategory {
                ListRootView(root: root, parentModel: model)
            } else {
                editor
            }
        }
        .padding()
        .opacity(hasFile || model.specialCategory ? 1 : 0)
        .transition(.scale)
    }

    func updateFile(url: URL) {
        root.editControllable.resetFile(url: url, in: model)
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
