// @copyright André Trettin

import SwiftUI

struct ConvertImageEditor: View {
    let model: PhotoModel

    @Environment(PhotoRootModel.self) private var root
    @State private var conversionErrorMessage: String?

    var body: some View {
        if root.editController.isNotJpegPhoto(itemId: model.id) {
            Button {
                Task {
                    do {
                        try await root.editController.convert(itemId: model.id)
                    } catch {
                        conversionErrorMessage = error.localizedDescription
                    }
                }
            } label: {
                Label {
                    Text("Convert to JPEG", bundle: .module)
                } icon: {
                    Image(systemName: "photo.badge.checkmark")
                }
            }
            .alert(
                Text("Conversion Failed", bundle: .module),
                isPresented: Binding(
                    get: { conversionErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            conversionErrorMessage = nil
                        }
                    }
                )
            ) {
                Button(role: .cancel) {
                    conversionErrorMessage = nil
                } label: {
                    Text("OK", bundle: .module)
                }
            } message: {
                Text(verbatim: conversionErrorMessage ?? "")
            }
        }
    }
}

#Preview(traits: .mockData) {
    ConvertImageEditor(model: .preview)
}
