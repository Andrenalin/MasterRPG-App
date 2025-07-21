// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import PhotosUI
import SwiftUI

struct LibraryPhotoPicker: View {
    let prominent: Bool
    let updateImage: @Sendable (AKImage?) async -> Void
    
    @State private var selectedItem: PhotosPickerItem? = nil
    
    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .padding(8)
                    .imageScale(prominent ? .large : .medium)
                    .background {
                        prominent ? Color.accentColor : .clear
                    }
                    .tint(prominent ? .white : Color.accentColor)
#if os(iOS)
                    .hoverEffect(.highlight)
#endif
                    .clipShape(.capsule)
#if !os(visionOS)
                    .glassEffect()
#endif
            } else {
                Image(systemName: "photo")
#if os(iOS) || os(visionOS)
                    .font(.system(size: 18))
                    .padding(8)
                    .imageScale(prominent ? .large : .medium)
                    .background {
                        prominent ? Color.accentColor : .clear
                    }
                    .tint(prominent ? .white : .primary)
#if os(iOS)
                    .background(.ultraThinMaterial)
                    .hoverEffect(.highlight)
#endif
                    .clipShape(.circle)
                    .shadow(color: .primary, radius: 4)
#endif
            }
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
    LibraryPhotoPicker(prominent: true) { _ in }
}

#endif
