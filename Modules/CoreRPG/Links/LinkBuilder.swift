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

    /// The one pattern that finds a markdown link `[label](target)` in text, of any target, not
    /// only the app's. The label has no brackets, so in `[a [b](x)` only `[b](x)` is the link;
    /// the target runs to the first `)`. `withoutLink()`, `IntentEntityText.readable` and the
    /// Quick Link scanner use it. See CODE_AUDIT_Since_3.0.1 §9.3.
    public static var markdownLinkPattern: Regex<(Substring, label: Substring, target: Substring)> {
        #/\[(?<label>[^\[\]]*)\]\((?<target>[^)]*)\)/#
    }

    /// `text` with every markdown link replaced by its label.
    public static func labels(in text: String) -> String {
        text.replacing(markdownLinkPattern) { String($0.output.label) }
    }
}
