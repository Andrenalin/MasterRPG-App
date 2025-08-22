// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

public struct ItemDetailEditorView: View {
    public init(root: any ItemRootControllable, model: ItemDataModel) {
        self.root = root
        self.model = model
        self.cacheItemListModel = CacheItemListModel()
    }

    let root: any ItemRootControllable
    let model: ItemDataModel
    let cacheItemListModel: CacheItemListModel

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
        ZStack(alignment: .top) {
            Color.clear
                        
            initialFileImporterView

            backgroundView

            VStack {
                contentView

                //bottomView
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
            Text("Inspector")
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
        //Rectangle().fill(model.module.color.gradient)
        Color.clear.frame(height: 120)
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
//
//
//    @ViewBuilder
//    var backgroundView: some View {
//        background
//            .background {
//                Rectangle().fill(EditController.Model.typeId.color.gradient)
//                    .ignoresSafeArea(edges: .top)
//                    .backgroundExtensionEffect()
//            }
//    }
//
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
//
//    @ViewBuilder
//    var bottomView: some View {
//        if hasFile && model.specialCategory == false {
//            CarouselItemView(model: model, editController: editController, selection: selection) {
//                bottom
//            }
//            .frame(maxWidth: .infinity, alignment: .leading)
//            .fixedSize(horizontal: false, vertical: true)
//            .padding(.top, 2)
//            .environment(selection)
//            .transition(.move(edge: .bottom))
//        }
//    }
//
    @ViewBuilder
    var contentView: some View {
        VStack(spacing: 8) {
            ItemDetailOverlayView(model: model)

            // editor
            
//            if model.specialCategory {
//                ItemListView(listController: listController, editController: editController, menuController: menuController, parentModel: model, module: EditController.Model.typeId) { id in
//                    route(id)
//                } row: { itemId in
//                    row(itemId)
//                }
//            }
        }
        .padding()
        .opacity(hasFile || model.specialCategory ? 1 : 0)
        .transition(.scale)
    }

    func updateFile(url: URL) {
        root.editControllable.resetFile(url: url, in: model)
    }
}

#Preview("Folder", traits: .mockData) {
    @Previewable @Environment(FakeItemRootController.self) var root
    @Previewable @Query var models: [ItemDataModel]
    
    NavigationStack {
        DetailRootView(model: models.first(where: { $0.id == MockData.folderId })!)
    }
    .preferredColorScheme(.dark)
}
