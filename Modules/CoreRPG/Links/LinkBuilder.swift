// @copyright André Trettin

import Foundation

/// The one place that spells out the in-app link grammar:
///
///     RPG://<module token>/<link number>/<item id>[/<entry id>][/<command>]
///
/// and its markdown form `[name](address)`. Each call site used to assemble these strings by
/// hand, so a grammar change meant editing eight places (and the Foundry copy already escaped
/// the name where the others did not). See CODE_AUDIT_15 §9.15.
public enum LinkBuilder {
    public static func address(
        module: NetworkModules,
        linkNumber: Int = 0,
        itemId: UUID,
        entryId: UUID? = nil,
        command: String? = nil
    ) -> String {
        var address = "\(URL.appScheme)://\(module.token)/\(linkNumber)/\(itemId.uuidString)"
        if let entryId {
            address += "/\(entryId.uuidString)"
        }
        if let command {
            address += "/\(command)"
        }
        return address
    }

    public static func markdown(
        name: String,
        module: NetworkModules,
        linkNumber: Int = 0,
        itemId: UUID,
        entryId: UUID? = nil,
        command: String? = nil
    ) -> String {
        "[\(name)](\(address(module: module, linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)))"
    }
}
