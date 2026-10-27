// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

@AppIntent(schema: .system.search)
public struct SearchAdventuresIntent: ShowInAppSearchResultsIntent {
    public static let title: LocalizedStringResource = "Search Adventures"
    public static let description = IntentDescription(
        "Shows the adventures that match a search term in the app.",
        categoryName: "Adventure",
        searchKeywords: ["find", "campaign"]
    )
    public static let searchScopes: [StringSearchScope] = [.general]

    public var criteria: StringSearchCriteria

    @Dependency var root: AdventureRootModel
    @Dependency var navigator: Navigator

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        root.searchModel.searchText = criteria.term
        await navigator.perform(route: KnownRoutes.adventures(nil, nil))
        return .result()
    }
}


#if os(iOS)
extension SearchAdventuresIntent: TargetContentProvidingIntent {}
#endif

#endif
