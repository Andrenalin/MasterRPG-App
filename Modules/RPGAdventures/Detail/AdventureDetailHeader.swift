// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPhotos

@MainActor
struct AdventureDetailHeader: View {
    let editController: EditController
    let model: AdventureModel
    let size: CGSize
    let topMargin: CGFloat
    let inline: Bool

#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @Environment(AdventureRoot.self) private var root

    @State private var isReading = false
    @State private var image: AKImage?

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
                AdventureSheet(model: editController.model, showImage: true, dismissAction: nil)
                    .environment(\.showGame, false)
            }
    }

    private var overlayButton: some View {
        ImageOverlayButton(icon: "book\(isReading ? ".fill": "")") {
#if os(visionOS) || os(macOS)
            openWindow(id: WindowIdentifier.adventureViewer.rawValue, value: ItemSelection(itemId: editController.model.id, entryId: nil))
#else
            isReading.toggle()
#endif
        }
    }

    private var photoId: Binding<UUID?> {
        Binding { model.photoId } set: { _ in }
    }
}
