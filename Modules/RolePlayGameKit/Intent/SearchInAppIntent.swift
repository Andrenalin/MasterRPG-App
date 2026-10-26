// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GameRPG
import AppIntents

/// The app-wide "search in MasterRPG" entry point for iOS 27, which renamed the system search
/// schema to `.system.searchInApp`. It is one intent for the whole app because the schema is a
/// single system entry point: it fills the cross-module search and shows it. The per-module
/// `Search…Intent`s use the deprecated `.system.search` name and stay for iOS 26.
/// See CODE_AUDIT_AppIntents §4.1.
@available(iOS 27, macOS 27, visionOS 27, *)
@AppIntent(schema: .system.searchInApp)
public struct SearchInAppIntent: ShowInAppSearchResultsIntent {
    public static let searchScopes: [StringSearchScope] = [.general]

    public var criteria: StringSearchCriteria

    @Dependency var appModel: AppModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        appModel.gameRoot.showSearchResults(for: criteria.term)
        appModel.routeToModule(.search)
        return .result()
    }
}

#if os(iOS)
@available(iOS 27, *)
extension SearchInAppIntent: TargetContentProvidingIntent {}
#endif

#endif
