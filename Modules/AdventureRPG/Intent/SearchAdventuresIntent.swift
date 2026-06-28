// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

@AppIntent(schema: .system.search)
struct SearchAdventuresIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Adventures"
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @Dependency var root: AdventureRootModel
    @Dependency var navigator: Navigator

    @MainActor
    func perform() async throws -> some IntentResult {
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.adventures(nil, nil))
        return .result()
    }
}


#if os(iOS)
extension SearchAdventuresIntent: TargetContentProvidingIntent {}
#endif

#endif
