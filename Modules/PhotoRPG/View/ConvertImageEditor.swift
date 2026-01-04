// @copyright André Trettin

import SwiftUI

struct ConvertImageEditor: View {
    let model: PhotoModel
    
    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        if root.editController.isNotJpegPhoto(itemId: model.id) {
            Button {
                Task {
                    try? await root.editController.convert(itemId: model.id)
                }
            } label: {
                Label {
                    Text("Convert to JPEG", bundle: .module)
                } icon: {
                    Image(systemName: "photo.badge.checkmark")
                }
            }
        }
    }
}

#Preview(traits: .mockData) {
    ConvertImageEditor(model: .preview)
}
