// @copyright André Trettin

import Foundation

/// Shared `token/uuid` parsing for `Route` enums whose `RawRepresentable`
/// conformance encodes each case as a `"token/\(id.uuidString)"` string.
/// Every module previously hand-copied the same split/parse/switch
/// boilerplate in its own `init?(rawValue:)`. See CODE_AUDIT_Table §9.6.
public enum TaggedIdRoute {
    /// Builds the `rawValue` string for a case tagged `token` wrapping `id`.
    public static func rawValue(token: String, id: UUID) -> String {
        "\(token)/\(id.uuidString)"
    }

    /// Parses a `"token/uuid"` string, handing the recognized `token` and
    /// parsed `UUID` to `resolve` to build the concrete case — or `nil` if
    /// the string isn't shaped like `token/uuid` or the `UUID` doesn't parse.
    public static func parse<Route>(
        _ rawValue: String,
        resolve: (_ token: Substring, _ id: UUID) -> Route?
    ) -> Route? {
        let values = rawValue.split(separator: "/")
        guard let token = values.first,
              let idString = values.last,
              let uuid = UUID(uuidString: String(idString))
        else { return nil }
        return resolve(token, uuid)
    }
}
