// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(WeatherRootModel.self) var root
    WeatherPhotoEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}

struct WeatherPhotoEditor: View {
    let model: WeatherModel

    @Environment(WeatherRootModel.self) private var root

    var body: some View {
        Section {
            root.viewController.photoSelection(root: root, selectionModel: root.editController.weatherEditModel.selectionPhoto)
                .onChange(of: root.editController.weatherEditModel.selectionPhoto.selection) {
                    withAnimation(.easeInOut) { root.editController.add(photoId: root.editController.weatherEditModel.selectionPhoto.itemId, itemId: model.id) }
                }
                .onChange(of: model.photoId, initial: true) {
                    withAnimation(.easeInOut) { root.editController.weatherEditModel.selectionPhoto.resetSelection(itemId: model.photoId, entryId: nil) }
                }
        } header: {
            WeatherSectionHeader(titleKey: "Photo", bundle: .module)
        }
    }
}
