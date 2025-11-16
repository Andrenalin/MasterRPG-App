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
        if let model = root.itemController.itemSync(for: selection.itemId) {
            switch model.genType {
            case .adventure:
                AdventureGenRootView(model: model)
            case .character:
                ChatRootView(model: model)
            case .extractor:
                ExtractorGenRootView(model: model)
            }
        }
    }

    @MainActor @ViewBuilder
    func inlineViewer(root: GeneratorRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        if let model = root.itemController.itemSync(for: id) {
            switch model.genType {
            case .adventure:
                AdventureGenRootView(model: model, dismissAction: dismissAction)
            case .character:
                ChatRootView(model: model, dismissAction: dismissAction)
            case .extractor:
                ExtractorGenRootView(model: model, dismissAction: dismissAction)
            }
        }
    }
}
