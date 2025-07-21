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
    @Environment(PhotoRootModel.self) private var root

    @State var selection = DetailPhotoSelection()
    @State private var isEditing = false
    @State private var showImporter = false

    var body: some View {
        let _ = Self._printChanges()

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
#if !os(tvOS)
        .toolbar(removing: .title)
#endif
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
    }

    private var detailView: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .center) {
                    PlainPhotoView(cacheController: root.cacheController, model: selection.selectedPhoto ?? model, ratio: .fit)
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
                        Spacer()
                        HStack(spacing: 40) { PhotoImporterView(model: model, prominent: true)
                        }
                        Spacer()
                        Spacer()
                    }
                }
            }

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
                if showImporter {
                    PhotoImporterView(model: model, prominent: false)
                }
                GlassButton {
                    withAnimation(.bouncy(duration: 0.3)) {
                        showImporter.toggle()
                    }
                } label: {
                    Image(systemName: "photo.badge.plus")
                }
                .animation(.bouncy, value: model.url)
                .transition(.scale.combined(with: .opacity))
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
