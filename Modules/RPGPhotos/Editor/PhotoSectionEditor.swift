// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PhotoSectionEditor: View {
    let editController: EditController
    let model: PhotoModel
    
    @Environment(PhotoRoot.self) private var root

    var body: some View {
        @Bindable var model = model
        
        Section {
            PhotoOrientationEditor(editController: editController)

            FileLocationEditor(editController: editController, fileStore: root.fileUrlDataController, fileUrlBinding: $model.fileUrl)

            ConvertImageEditor(editController: editController, model: model)
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Photo", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .animation(.bouncy, value: editController.isNotJpegPhoto())
    }
}
