// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PhotoImporterView: View {
    @Binding var showImporter: Bool
    let updateImage: @Sendable (AKImage?) async -> Void
    
    @State private var showCamera = false
    
    var body: some View {
        HStack {
#if !os(tvOS)
#if os(iOS)
            ImageOverlayButton(icon: "camera\(showCamera ? ".fill" : "")") { showCamera.toggle() }
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                .opacity(CaptureImagePicker.isCameraAvailable ? 1 : 0)
#endif
            LibraryPhotoPicker(updateImage: updateImage)
            
            ImageOverlayButton(icon: "folder\(showImporter ? ".fill" : "")") { showImporter.toggle() }
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
#endif
        }
#if os(iOS)
        .sizedSheet(isPresented: $showCamera) {
            CaptureImagePicker(shown: $showCamera, updateImage: updateImage)
        }
#endif
    }
}

#Preview {
    Color
        .teal
        .frame(width: 256, height: 256)
        .overlay(PhotoImporterView(showImporter: .constant(true)) { _ in }, alignment: .bottom)
}
