// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct RootImageViewer: View {
    let model: PhotoModel
    let size: CGSize
    let toolBarModel: GameToolBarModel
    let isGame: Bool
    let dismiss: (() -> Void)?
    
    var body: some View {
        AsyncPhoto(model: model) { image, photoDegrees in
            ImageViewer(image: image, photoDegrees: photoDegrees, containerSize: size, toolBarModel: toolBarModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            GameToolBar(model: toolBarModel, hideCloseButton: isGame, dismiss: dismiss)
                .padding()
        }
    }
}
