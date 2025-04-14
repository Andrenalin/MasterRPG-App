// @copyright André Trettin

import AndrenalinKit
import SwiftUI

@MainActor
struct ValueDetailHeader: View {
    let model: ValueModel
    let size: CGSize
    let topMargin: CGFloat
    let inline: Bool
    
#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @Environment(ValueRoot.self) private var root
    
    @State private var isReading = false
    
    var body: some View {
        root.photoRoot.viewController.headerView(with: photoId, size: size, topMargin: topMargin)
#if os(iOS)
            .toolbar {
                ToolbarItem {
                    if inline == false {
                        overlayButton
                    }
                }
            }
#else
            .overlay(alignment: .topTrailing) {
                overlayButton
                    .padding([.top, .trailing])
            }
#endif
            .sheetFullScreen(isPresented: $isReading) {
                CharacterSheet(model: model, showTopImage: true, dismissAction: nil)
                    .environment(\.showGame, false)
            }
    }
    
    private var overlayButton: some View {
        ImageOverlayButton(icon: "book\(isReading ? ".fill": "")") {
#if os(visionOS) || os(macOS)
            openWindow(id: WindowIdentifier.valueViewer.rawValue, value: ItemSelection(itemId: model.id, entryId: nil))
#else
            isReading.toggle()
#endif
        }
    }
    
    private var photoId: Binding<UUID?> {
        Binding { model.photoId } set: { _ in }
    }
}

#Preview {
    ValueDetailHeader(model: .preview, size: CGSize(width: 320, height: 600), topMargin: 64, inline: false)
        .environment(ValueRoot.preview)
    
}
