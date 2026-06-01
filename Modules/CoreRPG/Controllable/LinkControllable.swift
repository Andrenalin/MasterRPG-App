// @copyright André Trettin

import SwiftUI
import os.log

public enum LinkType: String, Equatable, Hashable, Sendable, CaseIterable {
    case photoImmersive
    case play
    case remove
    case roll
    case share
    case show
    case favorite
    
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .photoImmersive: "Immersive"
        case .play: "Play"
        case .remove: "Remove"
        case .roll: "Roll"
        case .share: "Share"
        case .show: "Show"
        case .favorite: "Favorite"
        }
    }
    
    var title: String {
        String(localized: localizedTitle).localizedString
    }
    
    var icon: String {
        switch self {
        case .photoImmersive: "photo.fill"
        case .play: "play.fill"
        case .remove: "trash.fill"
        case .roll: "dice.fill"
        case .share: "square.and.arrow.up.fill"
        case .show: "eye.fill"
        case .favorite: "star.fill"
        }
    }
    
    public var linkNumberAddition: Int {
        switch self {
        case .photoImmersive: 100
        case .play: 200
        case .remove: 300
        case .roll: 400
        case .share: 500
        case .show: 600
        case .favorite: 700
        }
    }
}

public protocol LinkControllable: Sendable {
    var rootManager: RootManager { get }
    var itemControllable: any ItemControllable { get }
    

    // MARK: - Handle Link
    @MainActor func handleTextLink(url: URL, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String
    
    @MainActor func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String
    
    @MainActor func toggleLink(module: NetworkModules, linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?) -> String
    @MainActor func toggleLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?) -> String
    
    // MARK: Generate Links
    @MainActor func generateLink(linkNumber: Int, itemId: UUID, entryId: UUID?) -> String

    // MARK: Repair
    @MainActor func repairLink(_ link: LinkReplaceModel, for content: String, for categories: [ItemListCategory]) -> String
    @MainActor func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String

    // MARK: Validate
    @MainActor func validateLinks(reportModel: ValidateRepairModel) async
    @MainActor func validateLinks(on itemId: UUID)

    // Link
    @MainActor func link(for name: String, entryName: String?) -> String?
    @MainActor func linkEntries(for itemId: UUID) -> [LinkEntryModel]
    @MainActor func link(for module: NetworkModules) -> [LinkEntryModel]
    @MainActor func name(for id: UUID, entryId: UUID?) -> String
        
    // Collect Links
    @MainActor func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID]
}

// MARK: - generate Links

public extension LinkControllable {
    @MainActor var rootLinkControllable: LinkControllable {
        rootManager.adventureRoot.linkControllable
    }
    
    @MainActor
    func generateLink(item: ItemRowTreeModel) -> String {
        generateLink(linkNumber: 0, itemId: item.model.itemId, entryId: item.model.entryId)
    }

    @MainActor
    func generateLink(model: ItemRowModel) -> String {
        generateLink(linkNumber: 0, itemId: model.itemId, entryId: model.entryId)
    }

    @MainActor
    func generateLink(itemId: UUID) -> String {
        generateLink(linkNumber: 0, itemId: itemId, entryId: nil)
    }

    @MainActor
    func generateLink(linkNumber: Int, itemId: UUID, entryId: UUID?) -> String {
        guard let entryId else { return itemControllable.itemOrEmpty(for: itemId).url(linkNumber: linkNumber) }
        return itemControllable.itemOrEmpty(for: itemId).url(linkNumber: linkNumber, entryId: entryId)
    }

    @MainActor
    func generateLinks(itemId: UUID, into content: String) async -> String {
        generateLinks(itemId: itemId, entryId: nil, into: content)
    }

    @MainActor
    func generateLinks(itemId: UUID, entryId: UUID? = nil, into content: String) -> String {
        let link: String = generateLink(linkNumber: 0, itemId: itemId, entryId: entryId)
        if content.contains(link) {
            return content.replacingOccurrences(of: link, with: "")
        }
        return content + "\(link)"
    }
    
    @MainActor
    func generateLinkAdr(linkNumber: Int, itemId: UUID, entryId: UUID?) -> String {
        guard let entryId else { return itemControllable.itemOrEmpty(for: itemId).urlAdr(linkNumber: linkNumber) }
        return itemControllable.itemOrEmpty(for: itemId).urlAdr(linkNumber: linkNumber, entryId: entryId)
    }
    
    @MainActor
    func specialLink(linkType: LinkType, linkNumber: Int, itemId: UUID, entryId: UUID?) -> String {
        let linkNumber = linkNumber >= 100 ? linkNumber : linkType.linkNumberAddition + linkNumber
        let urlAdr = generateLinkAdr(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
        return "[\(linkType.title)](\(urlAdr)/\(linkType.rawValue))"
    }
}

// MARK: - Handle Links

public extension LinkControllable {
    @MainActor
    func handleTextLink(url: URL, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        let module = url.moduleIdentifier
        guard module == itemControllable.config.module else { return text }

        guard let itemId = url.itemId else { return text }
        guard let brokenLink = brokenTextLinkToggle(url: url, itemId: itemId, entryId: nil, in: text) else {
            let linkText = toggleTextLink(linkNumber: url.linkNumber, itemId: itemId, entryId: url.childId, command: url.commandKey, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
            return linkText
        }
        return brokenLink
    }
    
    @MainActor
    func handleLink(url: URL, for itemId: UUID, in text: AttributedString, editAction: ((ItemRowModel) -> Bool)?) -> (OpenURLAction.Result, AttributedString) {
//        handleLink(url: url, for: itemId, in: text, shareResult: nil, toggler: nil) {
//            editAction?($0) ?? false
//        }
        return (.discarded, text)
    }
}

// MARK: - Toggle Links

public extension LinkControllable {
    @MainActor
    func toggleLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?) -> String {
        let item = itemControllable.itemOrEmpty(for: itemId)
        if let entryId, let entry = item.entries.first(where: { $0.id == entryId }) {
            return entry.linkContent()
        } else {
            return item.description
        }
    }
    
    @MainActor
    func toggleLink(module: NetworkModules, linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?) -> String {
        toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
    }
    
    @MainActor
    func brokenTextLinkToggle(url: URL, itemId: UUID, entryId: UUID?, in text: String) -> String? {
        guard !validateLink(itemId: itemId, entryId: entryId) else { return nil }
        return text.toggleLink(url: url.absoluteString, with: "🚨 \(String(localized: itemControllable.config.module.localizedTitle)) \(String(localized: "Link is broken", bundle: .module))")
    }

    @MainActor
    func toggleLink(linkNumber: Int, itemId: UUID, entryId: UUID?, in text: AttributedString, textGetter: @escaping (Observable) -> String) -> AttributedString {
        let item = itemControllable.itemOrEmpty(for: itemId)
        let link = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
        return text.toggleLink(url: link, with: textGetter(item))
    }
    
    @MainActor
    func toggleLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: AttributedString, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> AttributedString {
        text
    }
    
}

// MARK: - Repair Links

public extension LinkControllable {
    @MainActor func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String { content }

    @MainActor func repairLink(_ link: LinkReplaceModel, for content: String, for categories: [ItemListCategory]) -> String {

        guard link.module == itemControllable.config.module else { return content }
        guard !validateLink(itemId: link.itemId, entryId: link.entryId) else { return content }

        Logger.linkController.info("\(itemControllable.config.module.token, privacy: .public) \(link.markDown, privacy: .public) is gone")

        if link.entryId != nil {
            // Is item available for the entry? If not recovery not possible
            guard let model = itemControllable.itemSync(for: link.itemId) else {
                Logger.linkController.warning("\(itemControllable.config.module.token, privacy: .public) \(link.markDown, privacy: .public) cannot recover entry because item is missing.")
                return content.replacingOccurrences(of: link.markDown, with: link.name)
            }

            guard let entry = model.entries.first(where: { model.urlName(entryId: $0.id) == link.name }) else {
                Logger.linkController.warning("\(itemControllable.config.module.token, privacy: .public) \(link.markDown, privacy: .public) cannot recover entry because entry name is missing.")
                return content.replacingOccurrences(of: link.markDown, with: link.name)
            }
            return content.replacingOccurrences(of: link.markDown, with: model.url(linkNumber: link.linkNumber, entryId: entry.id))
        } else {
            let all = categories.contains(.all)
            var items: [(any ItemDataAccessable, Int)] = []
            for itemId in itemControllable.itemDataModel.items {
                if let model = itemControllable.itemSync(for: itemId), let index = all ? 0 : categories.firstIndex(of: model.category) {
                    items.append((model, index))
                }
            }
            items.sort { $0.1 < $1.1}

            guard let newItem = items.first(where: { $0.0.urlName() == link.name })?.0 else {
                Logger.linkController.warning("\(itemControllable.config.module.token, privacy: .public) \(link.markDown, privacy: .public) cannot recover item because it is missing.")
                return content.replacingOccurrences(of: link.markDown, with: link.name)
            }

            return content.replacingOccurrences(of: link.markDown, with: newItem.url(linkNumber: link.linkNumber))
        }
    }
}

// MARK: - Validate Links

public extension LinkControllable {
    @MainActor func validateLinks(reportModel: ValidateRepairModel) async {
        reportModel.update(phase: .validateLinks)
        for inspectedId in itemControllable.itemDataModel.items {
            reportModel.increaseCurrent()
            await Task.yield()
            guard !Task.isCancelled else { return }
            validateLinks(on: inspectedId)
        }
    }

    @MainActor func validateLinks(on itemId: UUID) {}

    /// Clears all registered links whose source is `item`, then re-registers `item.linkRegisterModels`.
    /// Call unconditionally inside `validateLinks(on:)` — safe no-op when the item has no links.
    @MainActor func resetLinkRegister<M: ItemLinkRegistable>(_ item: M) {
        let register = itemControllable.linkRegisterController
        var existing: [LinkRegisterModel] = []
        for links in register.model.items.values {
            existing.append(contentsOf: links.filter { $0.source.itemId == item.id })
        }
        register.deregister(links: existing)
        register.register(links: item.linkRegisterModels)
    }

    @MainActor func validateLink(itemId: UUID) -> Bool {
        validateLink(itemId: itemId, entryId: nil)
    }

    @MainActor func validateLink(itemId: UUID, entryId: UUID? = nil) -> Bool {
        guard let item = itemControllable.itemSync(for: itemId) else { return false }
        if let entryId {
            return item.entries.firstIndex(where: { $0.id == entryId }) != nil
        }
        return true
    }
}

// MARK: - Links

public extension LinkControllable {
    @MainActor func link(for name: String, entryName: String?) -> String? { nil }
    @MainActor func linkEntries(for itemId: UUID) -> [LinkEntryModel] { [] }
    @MainActor func link(for module: NetworkModules) -> [LinkEntryModel] { [] }
    
    @MainActor
    func name(for id: UUID, entryId: UUID? = nil) -> String {
        if let entryId {
            guard let item = itemControllable.itemSync(for: id) else { return "" }
            return item[entryId].name
        }
        return itemControllable.nameSync(itemId: id)
    }
}

// MARK: - Collect Links

public extension LinkControllable {
    @MainActor func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] { [] }
}

// MARK: - Format Inline Description

public extension LinkControllable {
    @MainActor func formatInlineDescription(description: String, entryCount: Int) -> String {
        let descriptionText: String
        if description.isEmpty {
            descriptionText = String(localized: "No description", bundle: .module)
        } else {
            descriptionText = description
        }

        let entriesText: String
        if entryCount == 0 {
            entriesText = String(localized: "has no entries", bundle: .module)
        } else if entryCount == 1 {
            entriesText = String(localized: "1 Entry", bundle: .module)
        } else {
            entriesText = String(localized: "\(entryCount) Entries", bundle: .module)
        }

        return "\(descriptionText) -- \(entriesText)"
    }
}
