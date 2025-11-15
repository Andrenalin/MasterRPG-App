// @copyright André Trettin

import AndrenalinKit
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .item
    public let thumbnailRowViewType: ThumbnailRowViewType = .none
}

extension ViewController: ViewControllable {}

// MARK: Viewer

public extension ViewController {
    @MainActor @ViewBuilder
    func windowViewer(root: GeneratorRootModel, selection: WindowItemSelection) -> some View {
        if let model = root.itemController.model(for: selection.itemId) {
            if model.genType == .adventure {
                AdventureGenRootView(model: model)
            } else {
                ChatRootView(model: model)
            }
            //.environment(root)
        }
    }

    @MainActor @ViewBuilder
    func inlineViewer(root: GeneratorRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        if let model = root.itemController.model(for: id) {
            if model.genType == .adventure {
                AdventureGenRootView(model: model, dismissAction: dismissAction)
                    //.environment(root)
            } else {
                ChatRootView(model: model, dismissAction: dismissAction)
                    //.environment(root)
            }
        }
    }
}
