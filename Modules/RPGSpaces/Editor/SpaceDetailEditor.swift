// @copyright André Trettin

import AndrenalinKit
import SwiftUI
internal import UniformTypeIdentifiers

struct SpaceDetailEditor: View {
    let editController: EditController
    let model: SpaceModel
    
    @Environment(SpaceRoot.self) private var root

    @State private var detailHeaderModel = DetailHeaderModel(minHeight: 144, maxHeight: 400, maxHeightFromScreenHeight: true)
    @State private var externalHeaderModel = ExternalHeaderModel()
    
    @State private var selection = GroupItemSelectionModel()
    
    var body: some View {
        @Bindable var model = model
        HeaderFooterContentScrollView {
            headerView()
        } content: {
            contentView()
        } footer: {
            bottomView()
        } background: {
            Rectangle()
                .fill(SpaceModel.typeId.color)
        }
        .focusedSceneValue(\.selectedSpace, $model.id)
        .environment(detailHeaderModel)
//        .environment(externalHeaderModel)
    }
    
    func headerView() -> some View {
        ZStack(alignment: .bottom) {
            ItemDetailOverlayView(model: model)
                .padding()
        }
        .overlay(alignment: .top) {
            navigationHeader.font(.title)
                .padding(.top, -64)
        }
    }
        
    var fileTypes: [UTType] {
        root.editController(type: .main).fileUrlDataController?.fileTypes ?? []
    }
    
    func hasFile() -> Bool {
        model.fileUrl?.rawUrl != nil || fileTypes.isEmpty
    }
    
    var navigationHeader: Text {
        Text("\(Image(systemName: SpaceModel.typeId.icon)) \(SpaceModel.typeId.title)")
    }

    @ViewBuilder func initialFileImporterView() -> some View {
        HStack {
            FileImporterView(editControllable: root.editController(type: .main), fileTypes: [.usdz])
                .padding(32)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.tint, lineWidth: 2)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(model.fileUrl == nil ? 1 : 0)
        .transition(.scale)
    }
    
    @ViewBuilder func bottomView() -> some View {
        if hasFile() { //}&& model.specialCategory == false && root.viewControllable.goupViewType != .none {
            CarouselItemView(root: root.rootController, model: model, selection: selection) {
                if root.viewController.goupViewType == .item {
                    ItemGroupItemView(root: root.rootController, model: model)
                } else {
                    //if let cacheControllable = root.cacheController {
                        //GroupedPhotoView(cacheController: cacheControllable, model: model)
                    //}
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .environment(selection)
            .transition(.move(edge: .bottom))
        }
    }


    @ViewBuilder func contentView() -> some View {
        ZStack {
            initialFileImporterView()
            
#if os(macOS)
            ScrollView {
                editorContentView()
            }
#else
            editorContentView()
#endif
        }
    }
    
    func editorContentView() -> some View {
        Group {
//            if model.specialCategory {
//                ItemDetailOverlayView(model: model, fullHeader: false, onlyDescription: true)
//                    .padding()
//                
//                ListRootView(root: root, parentModel: model)
//            } else {
                Form {
                    if model.description.isEmpty == false {
                        ItemDetailOverlayView(model: model, fullHeader: false, onlyDescription: true)
                    }

                    editor
                }
                .scrollBounceBehavior(.basedOnSize)
            //}
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        //.opacity(hasFile(model: model) || model.specialCategory ? 1 : 0)
        .transition(.scale)
//        .applyIf(hasOverlay) {
//            $0.safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
//                overlay.opacity(0)
//            }
//        }
    }
    
    @ViewBuilder
    var editor: some View {
        @Bindable var model = model
        
        HeaderEditor(editController: editController)

        FileLocationEditor(editController: editController, fileStore: root.fileUrlDataController, fileUrlBinding: $model.fileUrl)

        SpacesSectionEditor(editController: editController, model: model)
    }
}

struct SpaceExternalHeader: View {
    let editController: EditController
    let model: SpaceModel

    @Environment(SpaceRoot.self) private var root
    @Environment(ExternalHeaderModel.self) private var externalHeaderModel

    var body: some View {
#if os(tvOS)
        SpaceEditor(editController: editController)
            .environment(DetailHeaderModel(size: CGSize(width: 400, height: 400)))
#else
        SpaceViewer(root: root, id: model.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                ImageOverlayButton(icon: "xmark") {
                    externalHeaderModel.showExtHeader = false
                }
                .padding()
            }
#endif
    }
}

#Preview {
    SpaceDetailEditor(editController: .preview, model: .preview)
        .environment(SpaceRoot.preview)
        .environment(ListModel.preview)
}
