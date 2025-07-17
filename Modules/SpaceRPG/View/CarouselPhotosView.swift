// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct CarouselPhotosView: View {
    var model: SpaceDataModel

    @Environment(\.modelContext) private var modelContext
    @Environment(DetailPhotoSelection.self) private var selection
    @Environment(SpaceRootModel.self) private var rootModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack {
                photoView(photo: model, selectedPhoto: nil)

                ForEach(model.entryModels) { entry in
                    if let photo = SpaceDataModel.model(modelContext: modelContext, id: entry.spaceId) {
                        photoView(photo: photo, selectedPhoto: photo)
                            .overlay(alignment: .topTrailing) {
                                GlassButton {
                                    withAnimation { rootModel.editController.removeSubPhoto(photoId: photo.id, model: model) }
                                } label: {
                                    Image(systemName: "minus")
                                        .foregroundStyle(.red, .white)
                                }
                            }
                    }
                }

                dropPhotoView
            }
        }
    }
    
    @ViewBuilder
    var dropPhotoView: some View {
        DropItemArea {
            VStack {
                Text("Drop Photo")
                
                Image(systemName: "square.and.arrow.down")
                    .imageScale(.large)
            }
        } dropAction: { links in
            addLinks(links: links)
        }
        .padding(.horizontal, 12)
        .frame(height: 128)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.accentColor.secondary, lineWidth: 2)
        }
    }
    
    private func addLinks(links: [LinkData]) -> Bool {
        var result = true
        links.forEach { link in
            guard link.module == .photo else {
                result = false
                return
            }
            withAnimation { rootModel.editController.addSubPhoto(photoId: link.itemId, model: model) }
        }
        return result
    }
    
    func photoView(photo: SpaceDataModel, selectedPhoto: SpaceDataModel?) -> some View {
        PlainPhotoView(model: photo, highResolution: false)
            .frame(height: 128)
            .onTapGesture {
                withAnimation { selection.selectedPhoto = selectedPhoto }
            }
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
            .overlay {
                if photo.url != nil {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(selection.selectedPhoto?.id == selectedPhoto?.id ? Color.accentColor : Color.clear, lineWidth: 4)
                }
            }
#if !os(tvOS)
            .dropDestination(for: LinkData.self) { items, _ in
                guard !items.isEmpty else { return false }
                return addLinks(links: items)
            }
#endif

    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var photos: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    CarouselPhotosView(model: photos[0])
        .environment(DetailPhotoSelection())
        .environment(SpaceRootModel(modelContext: modelContext))
        .environment(CacheItemListModel())
}
