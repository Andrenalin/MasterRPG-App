// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import PhotosUI
import SwiftUI

struct LibraryPhotoPicker: View {
    let size: CGFloat
    let updateImage: @Sendable (AKImage?) async -> Void
    
    @State private var selectedItem: PhotosPickerItem? = nil
    
    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                Image(systemName: "photo")
                    .font(.system(size: size))
                    .padding(size / 3)
                    .tint(.primary)
#if os(iOS)
                    .hoverEffect(.highlight)
#endif
                    .clipShape(.capsule)
#if !os(visionOS)
                    .glassEffect()
#endif
        }
        .onChange(of: selectedItem) {
            guard let localItem = selectedItem else { return }
            Task.detached {
                if let data = try? await localItem.loadTransferable(type: Data.self) {
                    await updateImage(AKImage(data: data))
                }
            }
        }
    }
}

#Preview {
    LibraryPhotoPicker(size: 24) { _ in }
}

#endif
