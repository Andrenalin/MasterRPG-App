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
        "[\(escapedLabel(name))](\(address(module: module, linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)))"
    }

    /// A link label with `\`, `[` and `]` escaped by a backslash, so a name such as
    /// "Dragon [Ancient]" is one label. Every builder of `[label](address)` goes through here
    /// (or `markdown`), and the scanners read the escapes back with `unescapedLabel`.
    /// See CODE_AUDIT_28 §5.10.
    public static func escapedLabel(_ label: String) -> String {
        label
            .replacing("\\", with: "\\\\")
            .replacing("[", with: "\\[")
            .replacing("]", with: "\\]")
    }

    /// The label as the user wrote it: the backslash escapes of `escapedLabel` removed.
    public static func unescapedLabel(_ label: String) -> String {
        guard label.contains("\\") else { return label }
        var result = ""
        var escaped = false
        for character in label {
            if escaped {
                if !"\\[]".contains(character) { result.append("\\") }
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        if escaped { result.append("\\") }
        return result
    }

    /// The one pattern that finds a markdown link `[label](target)` in text, of any target, not
    /// only the app's. The label has no unescaped brackets, so in `[a [b](x)` only `[b](x)` is the link;
    /// the target runs to the first `)`. `withoutLink()`, `IntentEntityText.readable` and the
    /// Quick Link scanner use it. See CODE_AUDIT_Since_3.0.1 §9.3.
    public static var markdownLinkPattern: Regex<(Substring, label: Substring, target: Substring)> {
        #/\[(?<label>(?:\\.|[^\[\]\\])*)\]\((?<target>[^)]*)\)/#
    }

    /// `text` with every markdown link replaced by its label.
    public static func labels(in text: String) -> String {
        text.replacing(markdownLinkPattern) { unescapedLabel(String($0.output.label)) }
    }
}
