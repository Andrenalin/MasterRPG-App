// @copyright André Trettin

#if !os(tvOS)

import AndrenalinKit
import PhotosUI
import SwiftUI

struct LibraryPhotoPicker: View {
    let updateImage: @Sendable (AKImage?) async -> Void
    
    @State private var selectedItem: PhotosPickerItem? = nil
    
    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
            Image(systemName: "photo")
    #if os(iOS) || os(visionOS)
                .imageScale(.medium)
                .padding(8)
    #if os(iOS)
                .background(.ultraThinMaterial)
                .foregroundStyle(Color.teal)
                .hoverEffect(.highlight)
    #endif
                .clipShape(.circle)
                .shadow(color: .primary, radius: 4)
    #endif
        }
        .onChange(of: selectedItem) {
            guard let localItem = selectedItem else { return }
            Task {
                if let data = try? await localItem.loadTransferable(type: Data.self) {
                    await updateImage(AKImage(data: data))
                }
            }
        }
    }
}

#Preview {
    LibraryPhotoPicker { _ in }
}

#endif
