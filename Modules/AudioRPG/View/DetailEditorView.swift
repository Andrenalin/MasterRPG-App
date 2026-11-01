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
                itemId: model.id,
                module: root.configurable.module
            )

            Group {
                if let url = model.url {
                    Text(verbatim: url.path(percentEncoded: false))
                } else {
                    Text("No file is set", bundle: .module)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(model.specialCategory ? 0 : 1)
        .allowsHitTesting(!model.specialCategory)
        .accessibilityHidden(model.specialCategory)
        .disabled(model.specialCategory)
        .padding()
    }
}
