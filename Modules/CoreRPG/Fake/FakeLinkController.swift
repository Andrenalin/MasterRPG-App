// @copyright André Trettin

import SwiftUI

struct FakeLinkController: LinkControllable {
    var itemControllable: any ItemControllable
    var _rootManager: RootManager? = nil
    var rootManager: RootManager { _rootManager! }
    
    func handleTextLink(url: URL, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        text
    }
    
    func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        let insertText = "\(itemId.uuidString.prefix(4)): \(entryId?.uuidString.prefix(4) ?? "no entry") for linkNo. \(linkNumber)"
        let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
        return text.toggleLink(url: url, with: insertText)
    }
    
    @MainActor func toggleLink(module: NetworkModules, linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?) -> String {
        "\(itemId.uuidString.prefix(4)): \(entryId?.uuidString.prefix(4) ?? "no entry") for linkNo. \(linkNumber) in module \(module)"
    }
    
    @MainActor static let fake: FakeLinkController = {
        var controller = FakeLinkController(itemControllable: FakeItemController.fake)
        controller._rootManager = RootManager.preview(fake: ItemRootController.fake)
        return controller
    }()
}
