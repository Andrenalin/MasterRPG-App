// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    DetailEditorView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}

struct DetailEditorView: View {
    let root: AudioRootModel
    let model: AudioModel

    var body: some View {
        HStack {
            FileImporterView(
                editControllable: root.editController,
                fileTypes: root.editController.fileUrlDataController?.fileTypes ?? [],
                itemId: model.id
            )

            Text(model.url?.path(percentEncoded: false) ?? "No file is set")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(model.specialCategory ? 0 : 1)
        .padding()
    }
}
