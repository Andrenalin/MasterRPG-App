// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct RootImageViewer: View {
    let model: PhotoModel
    let size: CGSize
    let toolBarModel: GameToolBarModel
    let isGame: Bool
    let dismiss: (() -> Void)?

    @Environment(PhotoRoot.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        AsyncImageViewer(model: model, size: size, toolBarModel: toolBarModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.gradient)
            .overlay(alignment: .bottom) {
                GameToolBar(model: toolBarModel, hideCloseButton: isGame, dismiss: dismiss)
                    .padding()
            }
    }
}
