// @copyright André Trettin

import CoreRPG
import SwiftUI

struct CarouselPhotoView: View {
    let photoIds: ItemSelectionModel
    let selection: GroupItemSelectionModel

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack {
                ForEach(photoIds.selection, id: \.self.itemId) { photoSelection in
                    CarouselPhotoItemView(
                        photoSelection: photoSelection,
                        photoIds: photoIds,
                        groupSelection: selection
                    )
                    .frame(height: 128)
                }

                CarouselDropAreaView(photoIds: photoIds)
                    .frame(height: 128)
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .environment(selection)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root

    CarouselPhotoView(photoIds: ItemSelectionModel(selection: root.itemController.itemDataModel.items.map { WindowItemSelection(itemId: $0) }, isSingleSelection: false), selection: GroupItemSelectionModel())
}
