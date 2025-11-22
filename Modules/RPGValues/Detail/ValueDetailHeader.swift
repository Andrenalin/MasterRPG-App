// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import PhotoRPG

@MainActor
struct ValueDetailHeader: View {
    let model: ValueModel

#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @Environment(CharacterRootModel.self) private var root
    @Environment(DetailHeaderModel.self) private var headerModel

    @State private var isReading = false
    
    var body: some View {
        root.photoRoot.viewController.headerView(root: root.photoRoot, id: model.photoId, size: headerModel.size, topMargin: headerModel.topSafeAreaHeight)

#if os(iOS)
            .toolbar {
                ToolbarItem {
                    if headerModel.isInline == false {
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
}

#Preview {
    ValueDetailHeader(model: .preview)
        .environment(CharacterRootModel.preview)
        .environment(DetailHeaderModel(size: CGSize(width: 375, height: 200), topSafeAreaHeight: 0, isInline: false))

}
