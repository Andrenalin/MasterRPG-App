// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController: Sendable {
    public let thumbnailRowViewType: ThumbnailRowViewType = .none
}

extension ViewController: ViewControllable {}

// MARK: Viewer

public extension ViewController {
    @MainActor @ViewBuilder
    func viewer(root: GeneratorRootModel, itemId: UUID, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) -> some View {        
        if let model = root.itemController.itemSync(for: itemId) {
            AdventureGenRootView(model: model, dismissAction: dismissAction)
        }
    }
    
    @MainActor @ViewBuilder func inlineChat(root: GeneratorRootModel, sheetModel: SheetModel) -> some View {
        AdventureChatRootView(sheetModel: sheetModel, dismissAction: nil)
    }
}
