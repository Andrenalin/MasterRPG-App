// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .photo
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {}

// MARK: Viewer

public extension ViewController {
    @MainActor
    func linkWindow(root: PdfRootModel, isInspector: Bool = false) -> some View {
        LinkRootView(type: isInspector ? .inspector : .window)
            .environment(root)
    }

    @MainActor
    func windowViewer(root: PdfRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.modelSync(for: selection.itemId) ?? .newItem        
        return PdfViewerView(model: model, entryId: selection.entryId, withoutBookmark: false)
            .environment(root)
    }

    @MainActor
    func inlineViewer(root: PdfRootModel, with id: UUID, withoutBookmark: Bool, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.modelSync(for: id) ?? .newItem
        return PdfViewerView(model: model, withoutBookmark: withoutBookmark, dismissAction: dismissAction)
            .environment(root)
    }
}
