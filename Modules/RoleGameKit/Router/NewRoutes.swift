// @copyright André Trettin

import Foundation

import RPGAdventures
import RPGAudios
import RPGDie
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGValues
import RPGWeathers
import SwiftUI

struct NewAdventureRoute: View {
    let appModel: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
        AdventureFactory.rootExtendedView(for: appModel.adventureRoot, tabId: tabId)
            .environment(appModel.adventureRoot)
    }
}

struct NewDiceRoute: View {
    let appModel: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            DiceFactory.rootExtendedView(for: appModel.diceRoot, tabId: tabId)
                .environment(appModel.diceRoot)
    }
}

struct NewMapRoute: View {
    let appModel: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            MapFactory.rootExtendedView(for: appModel.mapRoot, tabId: tabId)
                .environment(appModel.mapRoot)
    }
}

struct NewTableRoute: View {
    let appModel: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            TableFactory.rootExtendedView(for: appModel.tableRoot, tabId: tabId)
                .environment(appModel.tableRoot)
    }
}

struct NewValueRoute: View {
    let appModel: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            ValueFactory.rootExtendedView(for: appModel.valueRoot, tabId: tabId)
                .environment(appModel.valueRoot)
    }
}

struct NewWeatherRoute: View {
    let appModel: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            WeatherFactory.rootExtendedView(for: appModel.weatherRoot, tabId: tabId)
                .environment(appModel.weatherRoot)
    }
}
