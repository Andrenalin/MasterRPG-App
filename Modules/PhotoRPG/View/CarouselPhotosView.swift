// @copyright André Trettin

import SwiftData
import SwiftUI

struct CarouselPhotosView: View {
    let model: PhotoDataModel

    @Environment(\.modelContext) private var modelContext
    @Environment(DetailPhotoSelection.self) private var selection

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack {
                if let entries = model.entries, !entries.isEmpty {
                    PlainPhotoView(model: model, size: .maxWidth, ratio: .fit)
                        .frame(height: 128)
                        .onTapGesture {
                            selection.selectedPhoto = nil
                        }
                }
                ForEach(model.entriesModel) { entry in
                    if let photo = photo(with: entry.photoId) {
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

    func photo(with id: UUID?) -> PhotoDataModel? {
        guard let id else { return nil }
        let fetchDesc = FetchDescriptor<PhotoDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        return models?.first { $0.id == id }
    }
}

#Preview {
    //CarouselPhotosView()
}
