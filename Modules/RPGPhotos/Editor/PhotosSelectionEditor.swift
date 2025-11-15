// @copyright André Trettin

import AndrenalinKit
import Observation
import SwiftUI

struct PhotosSectionEditor: View {
    let editController: EditController
    
    @Environment(PhotoRoot.self) private var root
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel
    
    var body: some View {
        @Bindable var model = editController.model
        ItemsSelectionEditor(editController: editController, model: $model.entries, title: "Photos", bundle: .module, value: .photo, minimumWidth: 128) {  entry in
            HStack {
                PhotosThumbnail(itemId: entry.photoId)
                Spacer()
            }
            .padding(4)
            .background(color, in: .rect(cornerRadius: 8.0))
        } selectorView: {
            root.viewController.viewSelect(root: root, filter: .all) {
                model.entries.map { ItemRowModel(itemId: $0.photoId, typeId: .photo) }
            } toggleSelection: { selection, _ in
                if let index = model.entries.firstIndex(where: { $0.photoId == selection.itemId }) {
                    model.entries.remove(at: index)
                } else {
                    model.entries.append(PhotoEntryModel(id: UUID(), photoId: selection.itemId))
                }
            } dismissAction: {
                selectionSheetLinkModel.selection = false
            }
        } valueFactory: { photoId in
            PhotoEntryModel(id: UUID(), photoId: photoId)
        }
    }
    
    var color: Color {
        (colorScheme == .light ? Color.gray : Color.black).opacity(0.2)
    }
}

#Preview {
    PhotosSectionEditor(editController: .preview)
        .environment(PhotoRoot.preview)
}
