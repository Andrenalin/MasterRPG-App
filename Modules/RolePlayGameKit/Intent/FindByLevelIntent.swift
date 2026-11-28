// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GameRPG
import AppIntents

/// Opens the cross-module search with a level search: "Give me level 4 adventures", "Any monster
/// for level 9 characters". Adventures match by their level tag or text, monsters (Characters in
/// the Monster category) by a level or challenge rating within one of the level.
///
/// No App Shortcut phrase: all 10 slots are taken. Siri reaches the level search through
/// `SearchInAppIntent` ("Search MasterRPG for level 4 adventures"), which reads the level from the
/// term; this intent is the parameterized form for Shortcuts and Apple Intelligence.
public struct FindByLevelIntent: AppIntent {
    public static let title: LocalizedStringResource = "Find by Level"
    public static let description = IntentDescription(
        "Shows the adventures written for a character level and the monsters whose level or challenge rating fits it.",
        categoryName: "Search",
        searchKeywords: ["level", "monster", "adventure", "challenge rating", "CR", "encounter"]
    )

    public static let supportedModes: IntentModes = .foreground

    public static var parameterSummary: some ParameterSummary {
        Summary("Find \(\.$kind) for level \(\.$level)") {
            \.$term
        }
    }

    @Parameter(
        title: "Level",
        // A literal: intent metadata extraction needs constants. Same as AdventurePartyFacts.maximumLevel.
        inclusiveRange: (1, 30),
        requestValueDialog: .localized("Which character level?", bundle: .module)
    )
    var level: Int

    @Parameter(title: "Kind", default: .all)
    var kind: LevelSearchKindOption

    @Parameter(title: "Search Term", description: "Further words the results must contain, such as dragon.")
    var term: String?

    @Dependency var appModel: AppModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let filter = LevelSearchFilter(level: level, kind: kind.searchKind)
        appModel.gameRoot.showLevelSearch(LevelSearchQuery(filter: filter, text: term ?? ""))
        appModel.routeToModuleWhenReady(.search)
        return .result()
    }
}

#if os(iOS)
extension FindByLevelIntent: TargetContentProvidingIntent {}
#endif

/// What Find by Level looks for.
enum LevelSearchKindOption: String, CaseIterable, AppEnum {
    case all
    case adventures
    case monsters

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Level Search Kind")
    }

    static let caseDisplayRepresentations: [LevelSearchKindOption: DisplayRepresentation] = [
        .all: DisplayRepresentation(title: "Adventures and Monsters", image: .init(systemName: "magnifyingglass")),
        .adventures: DisplayRepresentation(title: "Adventures", image: .init(systemName: "wand.and.stars"), synonyms: ["Scenarios", "Campaigns"]),
        .monsters: DisplayRepresentation(title: "Monsters", image: .init(systemName: "list.bullet.rectangle"), synonyms: ["Creatures", "Enemies"])
    ]

    var searchKind: LevelSearchKind? {
        switch self {
        case .all: nil
        case .adventures: .adventure
        case .monsters: .monster
        }
    }
}

#endif
