// @copyright André Trettin

import Foundation
import SwiftUI

public protocol LinkControllable: Sendable {
    var module: NetworkModules { get }
    var itemControllable: ItemControllable { get }
    
    @MainActor func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String
    @MainActor func generateLink(linkNumber: Int, itemId: UUID, entryId: UUID?) -> String
    
    // Sheet Entries
    @MainActor func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel?
}

public extension LinkControllable {
    @MainActor func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel? { nil }
    func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] { [] }

    @MainActor func handleTextLink(url: URL, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        guard module == url.moduleIdentifier, let itemId = url.itemId else { return text }
        
        guard let brokenLink = brokenTextLinkToggle(url: url, itemId: itemId, entryId: nil, in: text) else {
            let linkText = toggleTextLink(linkNumber: url.linkNumber, itemId: itemId, entryId: url.childId, command: url.commandKey, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
            return linkText
        }
        return brokenLink
    }
    
    func name(for id: UUID, entryId: UUID? = nil) -> String {
        guard let item = itemControllable.modelSync(for: id) else { return "" }
        if let entryId {
            return item[entryId].name
        }
        return item.name
    }
    
    func specialLink(linkType: LinkType, linkNumber: Int, itemId: UUID, entryId: UUID?) -> String {
        let linkNumber = linkNumber >= 100 ? linkNumber : linkType.linkNumberAddition + linkNumber
        let urlAdr = generateLinkAdr(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
        return "[\(linkType.title)](\(urlAdr)/\(linkType.rawValue))"
    }
    
    func generateLinkAdr(linkNumber: Int, itemId: UUID, entryId: UUID?) -> String {
        guard let item = itemControllable.modelSync(for: itemId) else { return "" }
        guard let entryId else { return item.urlAdr(linkNumber: linkNumber) }
        return item.urlAdr(linkNumber: linkNumber, entryId: entryId)
    }
}

private extension LinkControllable {
    func brokenTextLinkToggle(url: URL, itemId: UUID, entryId: UUID?, in text: String) -> String? {
        guard !validateLink(itemId: itemId, entryId: entryId) else { return nil }
        return text.toggleLink(url: url.absoluteString, with: "🚨 \(String(localized: module.localizedTitle)) Link is broken")
    }

    func validateLink(itemId: UUID, entryId: UUID? = nil) -> Bool {
        guard let item = itemControllable.modelSync(for: itemId) else { return false }
        if let entryId {
            return item.entries.firstIndex(where: { $0.id == entryId }) != nil
        }
        return true
    }
}
