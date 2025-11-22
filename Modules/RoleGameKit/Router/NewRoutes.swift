// @copyright André Trettin

import Foundation

import RPGAdventures
import RPGAudios
import RPGDie
import RPGMaps
import RPGPdfs
import PhotoRPG
import SpaceRPG
import RPGTables
import RPGValues
import RPGWeathers
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

struct NewMapRoute: View {
    let appModel: AppModel
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            MapFactory.rootExtendedView(for: appModel.mapRoot, tabId: tabId)
                .environment(appModel.mapRoot)
    }
}

struct NewTableRoute: View {
    let appModel: AppModel
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            TableFactory.rootExtendedView(for: appModel.tableRoot, tabId: tabId)
                .environment(appModel.tableRoot)
    }
}

struct NewValueRoute: View {
    let appModel: AppModel
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            ValueFactory.rootExtendedView(for: appModel.valueRoot, tabId: tabId)
                .environment(appModel.valueRoot)
    }
}
