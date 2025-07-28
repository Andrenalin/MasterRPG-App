// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct CarouselPhotosView: View {
    var model: PdfDataModel

    @Environment(\.modelContext) private var modelContext
    @Environment(GroupItemSelectionModel.self) private var selection
    @Environment(PdfRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()

        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack {
                photoView(photo: model, selectedPhoto: nil)

                ForEach(model.entryModels) { entry in
                    if let photo = PdfDataModel.model(modelContext: modelContext, id: entry.id) {
                        photoView(photo: photo, selectedPhoto: photo)
                            .overlay(alignment: .topTrailing) {
                                GlassButton {
                                    withAnimation { root.editController.removeSubPhoto(photoId: photo.id, model: model) }
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
            withAnimation { root.editController.addSubPhoto(photoId: link.itemId, model: model) }
        }
        return result
    }
    
    func photoView(photo: PdfDataModel, selectedPhoto: PdfDataModel?) -> some View {
        PlainPhotoView(cacheController: root.cacheController, model: photo, highResolution: false)
            .frame(height: 128)
            .onTapGesture {
                withAnimation { selection.selectedItem = selectedPhoto }
            }
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
            .overlay {
                if photo.url != nil {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(selection.selectedItem?.id == selectedPhoto?.id ? Color.accentColor : Color.clear, lineWidth: 4)
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
    @Previewable @Query var models: [PdfDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    CarouselPhotosView(model: models[0])
        .environment(GroupItemSelectionModel())
        .environment(PdfRootModel(modelContext: modelContext))
        .environment(CacheItemListModel())
}
