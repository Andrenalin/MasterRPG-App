// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

@Observable
final class DetailPhotoSelection {
    var selectedPhoto: PhotoDataModel?
}

struct DetailView: View {
    let model: PhotoDataModel
    
    @State var selection = DetailPhotoSelection()
    @State private var isEditing = false
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    var body: some View {
        @Bindable var model = model
        VStack {
            detailView
            
            CarouselPhotosView(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(selection)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(removing: .title)
        .onChange(of: model.id) {
            selection.selectedPhoto = nil
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
                    isEditing = false
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
                    PlainPhotoView(model: selection.selectedPhoto ?? model, ratio: .fit)
                        .stretchy()
                }
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom) {
                    DetailOverlayView(model: selection.selectedPhoto ?? model)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    toolbarButtons
                }
                .padding()
            }
        }
    }
    
    private var detailEditorView: some View {
        DetailEditorView(model: model) {
            isEditing = false
        }
        .background {
            RoundedRectangle(cornerRadius: 24).fill(.thickMaterial)
        }
        .frame(minWidth: 320, alignment: .center)
        .padding(40)
        .offset(y: 128)
        .transition(.scale)
        .animation(.bouncy, value: isEditing)
        .opacity(isEditing ? 1 : 0)
    }
    
    @ViewBuilder
    private var toolbarButtons: some View {
        LibraryPhotoPicker { _ in }
        GlassButton {
            isEditing = true
        } label: {
            Image(systemName: "photo")
        }

        GlassButton(isProminent: true) {
            isEditing = true
        } label: {
            Image(systemName: "pencil")
        }
    }
}

struct DetailOverlayView: View {
    let model: PhotoDataModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(model.name)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            HStack {
                TagItemRow(tags: model.tags)
            }
            Text(model.information)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .opacity(0.8)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var photos: [PhotoDataModel]
    DetailView(model: photos[0])
        .environment(PhotoRootModel())
        .environment(CacheItemListModel())
}
