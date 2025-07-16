// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class DetailPhotoSelection {
    var selectedPhoto: PhotoDataModel?
}

struct DetailView: View {
    let model: PhotoDataModel
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @Environment(PhotoRootModel.self) private var rootModel
    
    @State var selection = DetailPhotoSelection()
    @State private var isEditing = false
    @State private var showImporter = false
    @State private var showImagePlayground = false
    
    var body: some View {
        @Bindable var model = model
        VStack {
            detailView
            
            if model.url != nil {
                CarouselPhotosView(model: model)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(selection)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(removing: .title)
        .onChange(of: model.id) {
            withAnimation {
                selection.selectedPhoto = nil
                isEditing = false
            }
        }
        .overlay(alignment: .top) {
            #if os(iOS)
            if horizontalSizeClass == .regular {
                detailEditorView
            }
            #else
            detailEditorView
            #endif
        }
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(edges: .top)
#if os(iOS)
        .applyIf(horizontalSizeClass == .compact) {
            $0.sheet(isPresented: $isEditing) {
                DetailEditorView(model: model) {
                    withAnimation { isEditing = false }
                }
                .presentationContentInteraction(.resizes)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
#endif
        .sheet(isPresented: $showImagePlayground) {
            if #available(iOS 18.1, *) {
                ImageGenerationView()
            }
        }
    }
    
    private var detailView: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .center) {
                    PlainPhotoView(model: selection.selectedPhoto ?? model, ratio: .fit)
                        .stretchy()
                }
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if !os(tvOS)
            .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: [.image], updateFile: updatePhoto))
            #endif

            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom) {
                    DetailOverlayView(model: selection.selectedPhoto ?? model)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    toolbarButtons
                }
                .padding()
            }
            .overlay(alignment: .center) {
                if model.url == nil {
                    VStack {
                        GlassButton {
                            showImagePlayground.toggle()
                        } label: {
                            Image(systemName: "gear")
                        }

                        PhotoImporterView(model: model)
                    }
                }
            }

        }
    }
    
    private func updatePhoto(url: URL) {
        rootModel.editController.resetPhoto(url: url, in: model)
    }

    @ViewBuilder
    private var detailEditorView: some View {
        if isEditing {
            DetailEditorView(model: model) {
                withAnimation { isEditing = false }
            }
            .id(model.id)
            .background {
                RoundedRectangle(cornerRadius: 24).fill(.thickMaterial)
            }
            .frame(minWidth: 320, alignment: .center)
            .padding(40)
            .offset(y: 128)
            .transition(.scale)
            .animation(.bouncy, value: isEditing)
        }
    }
    
    @ViewBuilder
    private var toolbarButtons: some View {
        VStack(alignment: .center) {
            if model.url != nil {
                if showImporter {
                    photoImporterView
                }
                GlassButton {
                    withAnimation(.bouncy(duration: 0.3)) {
                        showImporter.toggle()
                    }
                } label: {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 24))
                        .padding(8)
                }
                .animation(.bouncy, value: model.url)
                .transition(.scale.combined(with: .opacity))
            }

            GlassButton(isProminent: true) {
                isEditing = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 24))
                    .padding(8)

            }
        }
    }
    
    @ViewBuilder
    private var photoImporterView: some View {
        GlassButton {
            showImagePlayground.toggle()
        } label: {
            Image(systemName: "gear")
        }

        CameraImporterView(model: model)
        
        LibraryImporterView(model: model)
        
        FileImporterView(model: model)
    }
}


#Preview(traits: .mockData) {
    @Previewable @Query var photos: [PhotoDataModel]
    DetailView(model: photos[0])
        .environment(PhotoRootModel())
        .environment(CacheItemListModel())
}
