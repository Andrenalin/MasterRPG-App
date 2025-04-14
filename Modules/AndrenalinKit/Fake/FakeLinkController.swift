// @copyright André Trettin

import SwiftUI

struct FakeLinkController: LinkControllable {
    func handleTextLink(url: URL, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        text
    }
    
    func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        let insertText = "\(itemId.uuidString.prefix(4)): \(entryId?.uuidString.prefix(4) ?? "no entry") for linkNo. \(linkNumber)"
        let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
        return text.toggleLink(url: url, with: insertText)
    }
    
    init(itemControllable: FakeItemController) {
        self.itemControllable = itemControllable
    }
    
    var itemControllable: any ItemControllable
    
    @MainActor
    static let fake = FakeLinkController(itemControllable: FakeItemController.fake)
    
    @MainActor
    func toggleLink(module: NetworkModules, linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?) -> String {
        "\(itemId.uuidString.prefix(4)): \(entryId?.uuidString.prefix(4) ?? "no entry") for linkNo. \(linkNumber) in module \(module)"
    }
}
