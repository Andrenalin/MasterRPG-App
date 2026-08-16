// @copyright André Trettin

import Foundation

/// A `LinkControllable` conformer for a link-free context — a
/// ``SimpleSheetEditingSession`` never has other items to link to, so
/// resolving/toggling a text link is always a no-op that hands text back
/// unchanged. Everything beyond the three methods below already has a
/// correct no-op default in `LinkControllable`'s protocol extension
/// (`Modules/CoreRPG/Controllable/LinkControllable.swift`) — empty arrays,
/// `nil`, identity transforms — which are the right answer here too, not
/// stand-ins for missing behavior.
public final class SimpleLinkController: LinkControllable, @unchecked Sendable {
    public init(itemControllable: any ItemControllable) {
        self.itemControllable = itemControllable
    }

    public let itemControllable: any ItemControllable

    public func handleTextLink(url: URL, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        text
    }

    public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        text
    }

    @MainActor public func toggleLink(module: NetworkModules, linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?) -> String {
        ""
    }
}
