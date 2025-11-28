// @copyright André Trettin

import Foundation

import RPGAdventures
import AudioRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import WeatherRPG
import SwiftUI

struct NewAdventureRoute: View {
    let appModel: AppModel
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
        AdventureFactory.rootExtendedView(for: appModel.adventureRoot, tabId: tabId)
            .environment(appModel.adventureRoot)
    }
}
