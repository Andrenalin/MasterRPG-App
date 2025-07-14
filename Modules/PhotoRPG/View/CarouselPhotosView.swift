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
                    PlainPhotoView(model: model, size: .maxWidth, ratio: .fit)
                        .frame(height: 128)
                        .onTapGesture {
                            selection.selectedPhoto = nil
                        }
                        .overlay(alignment: .top) {
                            LibraryImporterView(model: model)
                        }
                        .overlay(alignment: .bottom) {
                            FolderImporterView(model: model)
                        }
                        .overlay(alignment: .trailing) {
                            CameraImporterView(model: model)
                                .offset(x: 20)
                        }


                ForEach(model.entriesModel) { entry in
                    if let photo = PhotoDataModel.model(modelContext: modelContext, id: entry.photoId) {
                        PlainPhotoView(model: photo, size: .maxWidth, ratio: .fit)
                            .frame(height: 128)
                            .onTapGesture {
                                selection.selectedPhoto = photo
                            }
                    }
                }
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
