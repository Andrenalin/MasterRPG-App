// @copyright André Trettin

import CoreRPG
import SwiftUI

struct RootImageViewer: View {
    let model: PhotoModel
    let size: CGSize
    let toolBarModel: GameToolBarModel
    let isGame: Bool
    let dismiss: (() -> Void)?

    @Environment(PhotoRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        AsyncImageViewer(model: model, size: size, toolBarModel: toolBarModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.gradient)
    }
}
