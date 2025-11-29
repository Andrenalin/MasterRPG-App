// @copyright André Trettin

import CoreRPG
import Observation
import SwiftUI

struct SpacesSectionEditor: View {
    let editController: EditController
    let model: SpaceModel

    @Environment(SpaceRootModel.self) private var root
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel

    var body: some View {
        @Bindable var model = model
        ItemsSelectionEditor(editController: editController, model: $model.entries, title: "Spaces", bundle: .module, value: .space, minimumWidth: 128) {  entry in
            HStack {
                SpacesThumbnail(itemId: entry.spaceId)
                Spacer()
            }
            .padding(4)
            .background(color)
        } selectorView: {
            root.viewController.viewSelect(root: root, filter: .all) {
                model.entries.map { ItemRowModel(itemId: $0.spaceId, typeId: .space) }
            } toggleSelection: { selection, _ in
                if let index = model.entries.firstIndex(where: { $0.spaceId == selection.itemId }) {
                    model.entries.remove(at: index)
                } else {
                    model.entries.append(SpaceEntryModel(id: UUID(), spaceId: selection.itemId))
                }
            } dismissAction: {
                selectionSheetLinkModel.selection = false 
            }
        } valueFactory: { spaceId in
            SpaceEntryModel(id: UUID(), spaceId: spaceId)
        }
    }

    var color: Color {
        (colorScheme == .light ? Color.gray : Color.black).opacity(0.2)
    }
}

#Preview {
    SpacesSectionEditor(editController: .preview, model: .preview)
        .environment(SpaceRootModel.preview)
}
