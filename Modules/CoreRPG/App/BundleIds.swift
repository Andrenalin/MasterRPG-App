// @copyright André Trettin

import Foundation

/// The reverse-DNS prefixes every app-owned identifier is built from, so the four spellings
/// (`MasterRPG`, `gamemaster`, `masterrpg`, bare domain) live in one place. The composed
/// identifiers are registered externally (entitlements, Info.plist, App Store Connect, Game
/// Center, the keychain) and must never change; `BundleIdsTests` pins them.
/// See CODE_AUDIT_18 §9.17.
public enum BundleIds {
    /// The developer's reverse-DNS domain.
    public static let domain = "de.andretrettin"
    /// Prefix of app-internal identifiers: queues, keychain services, coding keys, UTTypes,
    /// the SharePlay activity and the App Group.
    public static let app = "\(domain).MasterRPG"
    /// The original product name: the iCloud container, Spotlight domain and in-app products.
    public static let product = "\(domain).gamemaster"
    /// Prefix of the Game Center achievement ids (registered in lower case).
    public static let achievement = "\(domain).masterrpg.achievement"

    /// `app` followed by `.suffix`.
    public static func app(_ suffix: String) -> String {
        "\(app).\(suffix)"
    }
}
