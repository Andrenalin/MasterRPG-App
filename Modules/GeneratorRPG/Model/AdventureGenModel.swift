// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels

@Generable(description: "The campaign is a collecxtion of adventure about the same topic, theme or a long running story.")
struct CampaignGenModel: Equatable {
    @Guide(description: "An exciting name for the campaign.")
    var name: String
    var description: String
    @Guide(description: "Tags to describe the campaign.", .maximumCount(4))
    var tags: [String]
        
    @Guide(description: "The collction of adventure.")
    @Guide(.maximumCount(5))
    var entries: [AdventureGenModel]
}

@Generable(description: "An adventure has usually a few localtions and quests. It can be a standalone adventure or a part of a campaign.")
struct AdventureGenModel: Equatable {
    @Guide(description: "An exciting name for the adventure.")
    var name: String
    var description: String
    @Guide(description: "Tags to describe the adventure.", .maximumCount(4))
    var tags: [String]
        
    @Guide(description: "The content of the table. Each entry represents one row.")
    @Guide(.minimumCount(5))
    var entries: [ScenarioGenModel]
}

@Generable(description: "The scenario is one location or simple quest of the game.")
struct ScenarioGenModel: Equatable {
    @Guide(description: "An exciting name for the scenario.")
    var name: String
    var description: String
    @Guide(description: "Tags to describe the scenario.", .maximumCount(4))
    var tags: [String]
        
    @Guide(description: "The content of the table. Each entry represents one row.")
    @Guide(.minimumCount(10))
    var entries: [EntryGenModel]
}

@Generable
struct EntryGenModel: Equatable {
    @Guide(description: "A short exciting title of the content.")
    var name: String
    var content: String
}

@Generable
enum AdventureType: Equatable {
    case campaign
    case adventure
    case scenario
}

#endif
