// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct CarouselPhotosView: View {
    let model: PhotoDataModel

    @Environment(\.modelContext) private var modelContext
    @Environment(DetailPhotoSelection.self) private var selection

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack {
                photoView(photo: model, selectedPhoto: nil)

                ForEach(model.entriesModel) { entry in
                    if let photo = PhotoDataModel.model(modelContext: modelContext, id: entry.photoId) {
                        photoView(photo: photo, selectedPhoto: photo)
                    }
                }
            }
        }
        .scrollClipDisabled()
    }
    
    func photoView(photo: PhotoDataModel, selectedPhoto: PhotoDataModel?) -> some View {
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
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var photos: [PhotoDataModel]
    CarouselPhotosView(model: photos[0])
        .environment(DetailPhotoSelection())
        .environment(PhotoRootModel())
        .environment(CacheItemListModel())
}
