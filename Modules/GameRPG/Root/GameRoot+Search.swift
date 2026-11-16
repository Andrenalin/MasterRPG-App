// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import GroupActivities
import os.log
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import SwiftUI
import WeatherRPG

// MARK: - Search Helpers

extension GameRoot {
    func rootController(for module: NetworkModules) -> ItemRootController {
        switch module {
        case .adventure:
            return adventureRoot.rootController
        case .audio:
            return audioRoot.rootController
        case .value:
            return characterRoot.rootController
        case .dice:
            return diceRoot.rootController
        case .map:
            return mapRoot.rootController
        case .pdf:
            return pdfRoot.rootController
        case .photo:
            return photoRoot.rootController
        case .rule:
            // `searchAllItems()` only ever produces `.rule` results when `ruleRoot` exists, so
            // this should never be reached with a nil `ruleRoot`. Assert loudly in debug builds
            // rather than silently mislabeling Adventure content as a Rule search result.
            guard let ruleRoot else {
                assertionFailure("rootController(for: .rule) called with a nil ruleRoot")
                return adventureRoot.rootController
            }
            return ruleRoot.rootController
        case .space:
            return spaceRoot.rootController
        case .table:
            return tableRoot.rootController
        case .weather:
            return weatherRoot.rootController
        default:
            return adventureRoot.rootController
        }
    }
}
