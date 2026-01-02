// @copyright André Trettin

import SwiftUI

struct ConvertImageEditor: View {
    let editController: EditController
    let model: PhotoModel
    
    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        Group {
            if editController.isNotJpegPhoto(modelId: model.id) {
                Button {
                    Task {
                        try? await editController.convert(modelId: model.id)
                    }
                } label: {
                    Label {
                        Text("Convert Photo to JPEG", bundle: .module)
                    } icon: {
                        Image(systemName: "photo.badge.checkmark")
                    }
                }
                .transition(.scale)
            }
        }
    }
}
