// @copyright André Trettin

import CoreData
import CryptoKit
import Foundation

/// A directional link from one item/entry to another, stored in the register keyed by `destination.itemId`.
public struct LinkRegisterModel: Equatable, Hashable, Sendable, Identifiable {
    /// `id` defaults to an id derived from the occurrence (source, destination, link number,
    /// command) instead of a random one: links re-derived during sync (`mergeUpdates`) got a
    /// new random id on each device, so every device deleted the other's row for the same link
    /// and inserted its own. Rows loaded from the store keep their persisted id; legacy random
    /// ids are replaced once, on their source's next save. See CODE_AUDIT_18 §5.12.
    public init(
        id: UUID? = nil,
        name: String,
        source: ItemRowModel,
        destination: ItemRowModel,
        linkNumber: Int? = nil,
        command: String? = nil,
        markDown: String? = nil
    ) {
        self.id = id ?? Self.occurrenceId(source: source, destination: destination, linkNumber: linkNumber, command: command)
        self.name = name
        self.source = source
        self.destination = destination
        self.linkNumber = linkNumber
        self.command = command
        self.markDown = markDown
    }

    public init(link: LinkReplaceModel, source: ItemRowModel) {
        self.init(
            name: link.name,
            source: source,
            destination: ItemRowModel(
                itemId: link.itemId,
                entryId: link.entryId,
                typeId: link.module
            ),
            linkNumber: link.linkNumber,
            command: link.command,
            markDown: link.markDown
        )
    }

    public let id: UUID
    public let name: String
    /// The item/entry that embeds the link (e.g. an AdventureEntry whose content text contains the markdown link).
    public let source: ItemRowModel
    /// The item/entry being referenced (used as the dictionary key in `LinkRegisterListModel.items`).
    public let destination: ItemRowModel
    /// Identifies this occurrence in its source text. Two links to the same destination
    /// remain distinct when their link numbers differ.
    public let linkNumber: Int?
    /// Action links such as `show` and `remove` belong to the same source text but are
    /// not standalone rows in a sheet.
    public let command: String?
    /// Raw markdown string `[name](scheme://module/0/uuid[/entryId])` as it appears in the source text.
    public var markDown: String? = nil
    
    public func duplicate() -> LinkRegisterModel {
        LinkRegisterModel(
            name: name,
            source: source,
            destination: destination,
            linkNumber: linkNumber,
            command: command,
            markDown: markDown
        )
    }
    
    public var urlMarkDown: String {
        LinkBuilder.markdown(
            name: name,
            module: destination.typeId,
            linkNumber: linkNumber ?? 0,
            itemId: destination.itemId,
            entryId: destination.entryId,
            command: command
        )
    }

    public var isSheetLink: Bool {
        command == nil
    }

    /// A name-based (v5-style, SHA-256) UUID of the occurrence, identical on every device.
    static func occurrenceId(source: ItemRowModel, destination: ItemRowModel, linkNumber: Int?, command: String?) -> UUID {
        let key = [
            source.itemId.uuidString, source.entryId?.uuidString ?? "-", String(source.typeId.rawValue),
            destination.itemId.uuidString, destination.entryId?.uuidString ?? "-", String(destination.typeId.rawValue),
            linkNumber.map(String.init) ?? "-", command ?? "-"
        ].joined(separator: "|")
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    func isSameOccurrence(as other: LinkRegisterModel) -> Bool {
        source == other.source &&
        destination == other.destination &&
        linkNumber == other.linkNumber &&
        command == other.command
    }
}

/// Implemented by item models so `EditControllable.saveChanges` can diff which links were added or removed on each save.
@MainActor
public protocol ItemLinkRegistrable {
    /// The item's unique identifier, used to locate existing register entries when resetting links.
    nonisolated var id: UUID { get }
    /// All links currently embedded in this item (used when no previous version exists, e.g. on first import).
    var linkRegisterModels: [LinkRegisterModel] { get }
    /// Returns the diff between `self` and `oldValue`; called on every save to register/deregister only what changed.
    func changedLinkRegisterModels(oldValue: Self) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel])
}

public extension ItemLinkRegistrable {
    var linkRegisterModels: [LinkRegisterModel] { [] }
    func changedLinkRegisterModels(oldValue: Self) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) { ([], []) }
}

/// In-memory store for all registered cross-module links.
///
/// `items` is keyed by `destination.itemId` for incoming/"used by" lookups, while
/// `sourceItems` is keyed by `source.itemId` for outgoing sheet lookups.
@MainActor
public final class LinkRegisterListModel: Sendable {
    public init() {}

    var context: NSManagedObjectContext?

    /// Dictionary keyed by destination item UUID; each value is the list of `LinkRegisterModel`s pointing to that destination.
    public private(set) var items: [UUID: [LinkRegisterModel]] = [:]

    /// Dictionary keyed by source item UUID; each value is the list of links embedded by that source item.
    public private(set) var sourceItems: [UUID: [LinkRegisterModel]] = [:]

    // Source item IDs whose links changed since the last savePendingLinks() call.
    // savePendingLinks() does a delete-and-replace for these source IDs from the current in-memory state.
    var pendingAffectedSourceIds: Set<UUID> = []
    /// The persisted rows could not be fetched, so the register is not what is stored. Nothing is
    /// saved or deleted from it until a fetch succeeds. See CODE_AUDIT_23 §5.12.
    var hydrationFailed = false
    
    func reset() {
        items = [:]
        sourceItems = [:]
    }

    /// Restores both directional indexes as one rollback operation.
    ///
    /// External imports snapshot the link register before repairing imported models. Keeping this
    /// mutation on the model prevents rollback from restoring only one side of the dual index.
    func restoreSnapshot(
        items: [UUID: [LinkRegisterModel]],
        sourceItems: [UUID: [LinkRegisterModel]],
        pendingAffectedSourceIds: Set<UUID>
    ) {
        self.items = items
        self.sourceItems = sourceItems
        self.pendingAffectedSourceIds = pendingAffectedSourceIds
    }

    /// Adds a link to both indexes. Returns `false` when the same source occurrence
    /// was already registered.
    @discardableResult
    func append(_ link: LinkRegisterModel) -> Bool {
        let destinationKey = link.destination.itemId
        let alreadyRegistered = items[destinationKey, default: []].contains {
            $0.isSameOccurrence(as: link)
        }
        guard !alreadyRegistered else { return false }

        items[destinationKey, default: []].append(link)
        sourceItems[link.source.itemId, default: []].append(link)
        return true
    }

    /// Removes a source-to-destination relationship from both indexes.
    @discardableResult
    func remove(_ link: LinkRegisterModel) -> Bool {
        let destinationKey = link.destination.itemId
        let sourceKey = link.source.itemId
        let previousCount = items[destinationKey, default: []].count

        items[destinationKey, default: []].removeAll {
            $0.isSameOccurrence(as: link)
        }
        sourceItems[sourceKey, default: []].removeAll {
            $0.isSameOccurrence(as: link)
        }
        return items[destinationKey, default: []].count != previousCount
    }

    /// Removes every link pointing to the exact destination item or entry from both indexes.
    func removeLinks(to destination: ItemRowModel) -> Set<UUID> {
        let destinationKey = destination.itemId
        let removedLinks = items[destinationKey, default: []].filter { $0.destination == destination }
        guard !removedLinks.isEmpty else { return [] }

        items[destinationKey, default: []].removeAll { $0.destination == destination }
        for link in removedLinks {
            sourceItems[link.source.itemId, default: []].removeAll {
                $0.source == link.source && $0.destination == link.destination
            }
        }
        return Set(removedLinks.map(\.source.itemId))
    }
}
