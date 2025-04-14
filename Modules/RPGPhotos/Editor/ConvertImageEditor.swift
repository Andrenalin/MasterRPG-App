// @copyright André Trettin

import SwiftUI

struct ConvertImageEditor: View {
    let editController: EditController
    let model: PhotoModel
    
    @Environment(PhotoRoot.self) private var root
    
    var body: some View {
        Group {
            if editController.isNotJpegPhoto() {
                Button {
                    Task {
                        try? await editController.convert()
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
