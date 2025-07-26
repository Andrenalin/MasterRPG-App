// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DetailView: View {
    let model: PhotoDataModel
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @Environment(PhotoRootModel.self) private var root
    
    @State var selection = GroupItemSelectionModel()
    @State private var isEditing = false
    @State private var showImporter = false
    
    var body: some View {
        VStack(spacing: 0) {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            bottomView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth, value: isEditing)
        .animation(.bouncy, value: model.url)
        .ignoresSafeArea(edges: .top)
#if !os(visionOS)
        .inspector(isPresented: $showImporter) {
            VStack {
                PhotoImporterView(model: model, prominent: true)
            }
        }
#endif
#if !os(tvOS)
        .toolbar(removing: .title)
#endif
        .onChange(of: model.id) {
            withAnimation {
                selection.selectedItem = nil
                isEditing = false
            }
        }
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
    }
}

extension DetailView {
    @ViewBuilder
    var contentView: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack {
                        detailView
                            .frame(minHeight: 600)
                            .id("Header")
                        
#if os(iOS)
                        if horizontalSizeClass == .regular && isEditing {
                            DetailEditorView(model: model) {
                                withAnimation { isEditing = false }
                            }
                            .id("Editor")
                            .transition(.slide)
                        }
#endif
                    }
                    .onChange(of: isEditing) {
                        if isEditing {
                            proxy.scrollTo("Editor", anchor: .top)
                        } else {
                            proxy.scrollTo("Header", anchor: .top)
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)
                .frame(height: geometry.size.height)
            }
        }
    }
    
    @ViewBuilder
    var bottomView: some View {
        if model.url != nil && !isEditing {
            CarouselPhotosView(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(selection)
                .transition(.move(edge: .bottom))
        }
    }

    private var detailView: some View {
        PlainPhotoView(cacheController: root.cacheController, model: selection.selectedItem ?? model, ratio: .fill)
                .stretchy()
        .mask(LinearGradient(
            gradient: Gradient(colors: [.black, .black, .black, .clear]),
            startPoint: .top, endPoint: .bottom))
#if !os(tvOS)
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: [.image], updateFile: updatePhoto))
#endif
        .overlay(alignment: .center) {
            if model.url == nil {
                VStack {
                    Spacer()
                    HStack(spacing: 40) {
                        PhotoImporterView(model: model, prominent: true)
                    }
                    Spacer()
                    Spacer()
                }
            }
        }
        .overlay(alignment: .bottom) {
            HStack(alignment: .bottom) {
                DetailOverlayView(model: selection.selectedItem ?? model)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                toolbarButtons
            }
            .padding()
        }
    }

    private func updatePhoto(url: URL) {
        root.editController.resetPhoto(url: url, in: model)
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
                PhotoInlineImporterView(model: model)
            }

            GlassButton {
                withAnimation(.bouncy(duration: 0.3)) {
                    showImporter.toggle()
                }
            } label: {
                Image(systemName: "link")
            }

            GlassButton(isProminent: true) {
                isEditing = true
            } label: {
                Image(systemName: "pencil")
            }
        }
    }
}


#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    DetailView(model: models[0])
        .environment(CacheItemListModel())
}
