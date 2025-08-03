// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DetailView: View {
    let model: PdfDataModel
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @Environment(PdfRootModel.self) private var root
    
    @State private var selection = GroupItemSelectionModel()
    @State private var isEditing = false
    @State private var showImporter = false
    
    var body: some View {
        VStack(spacing: 0) {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if !isEditing {
                        HStack(alignment: .bottom) {
                            DetailOverlayView(itemId: model.id, model: model, nameKeyPath: \.name, categoryKeyPath: \.category, tagsKeyPath: \.tags, descriptionKeyPath: \.information)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if model.url != nil {
                                toolbarButtons
                            }
                        }
                        .padding()
                        .transition(.slide)
                    }
                }
            
            bottomView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth, value: isEditing)
        .animation(.bouncy, value: model.url)
        .ignoresSafeArea(edges: .top)
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
//        if model.url != nil && !isEditing {
//            CarouselPhotosView(model: model)
//                .frame(maxWidth: .infinity, alignment: .leading)
//                .fixedSize(horizontal: false, vertical: true)
//                .environment(selection)
//                .transition(.move(edge: .bottom))
//        }
    }

    private var detailView: some View {
        PlainPhotoView(cacheController: root.cacheController, model: selection.selectedItem ?? model)
            .stretchy()
        .mask(LinearGradient(
            gradient: Gradient(colors: [.black, .black, .black, .clear]),
            startPoint: .top, endPoint: .bottom))
#if !os(tvOS)
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: FileController.fileTypes, updateFile: updateFile))
#endif
        .overlay(alignment: .center) {
            if model.url == nil {
                VStack {
                    Spacer()
                    HStack(spacing: 40) {
                        FileImporterView(model: model, prominent: true)
                    }
                    Spacer()
                    Spacer()
                }
            }
        }
    }

    private func updateFile(url: URL) {
        root.editController.resetFile(url: url, in: model)
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
                FileImporterView(model: model, prominent: false)
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
    @Previewable @Query var models: [PdfDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    DetailView(model: models[0])
        .environment(CacheItemListModel())
}
