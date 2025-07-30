// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DetailView: View {
    let model: PhotoDataModel
    
    @Environment(PhotoRootModel.self) private var root
    
    @State private var selection = GroupItemSelectionModel()
    
    var body: some View {
        ZStack(alignment: .top) {
            backgroundHeader
            VStack {
                @Bindable var model = model
                ZStack(alignment: .top) {
                    Color.clear
                    
                    FileDetailEditorView(model: model, editController: root.editController, nameKeyPath: \.name, categoryKeyPath: \.category, tagsKeyPath: \.tags, descriptionKeyPath: \.information, urlKeypath: \.url, fileTypes: FileController.fileTypes) {
                        VStack {
                            PhotoImporterView(model: model, prominent: true)
                        }
                    } inside: {
                        contentView
                    } editor: {
                        Picker("Degrees", selection: $model.degrees) {
                            Text("0°").tag(0.0)
                            Text("90°").tag(90.0)
                            Text("180°").tag(180.0)
                            Text("270°").tag(270.0)
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 6)
                        .padding(.horizontal)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        PhotoInlineImporterView(model: model)
                            .padding()
                    }
                }
                
                bottomView
            }
            .ignoresSafeArea(edges: .top)
        }
    }
    
    var backgroundHeader: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 8) {
                detailView
            }
        }
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(edges: .top)
        .backgroundExtensionEffect()
    }
    
    var contentView: some View {
        GeometryReader { geometry in
            Color.clear
//            ScrollView(showsIndicators: false) {
//                VStack {
//                    detailView
//                        .frame(minHeight: 600)
//                }
//                .scrollClipDisabled(true)
//            }
            .frame(height: geometry.size.height)
        }
        .mask(LinearGradient(
            gradient: Gradient(colors: [.black, .black, .black, .clear]),
            startPoint: .top, endPoint: .bottom))
    }
}

extension DetailView {
    
    @ViewBuilder
    var bottomView: some View {
        if model.url != nil {
            CarouselPhotosView(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(selection)
                .transition(.move(edge: .bottom))
        }
    }
    
    private var detailView: some View {
        PlainPhotoView(cacheController: root.cacheController, model: selection.selectedItem ?? model)
            .stretchy()
    }
}


#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    DetailView(model: models[0])
        .environment(CacheItemListModel())
}
