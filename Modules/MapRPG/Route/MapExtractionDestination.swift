// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import GeneratorRPG
import SwiftUI

/// The single-map "Extract Information" sheet: name, description and tags generated from the
/// map's rooms and its photo's description and tags.
struct MapExtractionDestination: View {
    let itemId: UUID

    @Environment(MapRootModel.self) private var root

    var body: some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        if MapSheetText.rooms(of: model).isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Rooms", bundle: .module)
                } icon: {
                    Image(systemName: "mappin.slash")
                }
            } description: {
                Text("This map has no rooms to analyze.", bundle: .module)
            }
        } else {
            TextSummaryExtractionView(
                module: .map,
                entriesText: MapSheetText.text(for: model, photoRoot: root.photoRoot),
                itemName: model.name,
                notice: MapSheetText.hasPhotoText(for: model, photoRoot: root.photoRoot)
                    ? nil
                    : LocalizedStringResource("Add a photo description and tags to improve the map information", bundle: .module)
            ) { content, selection in
                root.editController.applyExtractedContent(content, to: itemId, selection: selection)
            }
        }
    }
}

#Preview(traits: .mockData) {
    MapExtractionDestination(itemId: MapModel.previewEmptyId)
}
#endif
