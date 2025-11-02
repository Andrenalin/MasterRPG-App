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
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
        AdventureFactory.rootExtendedView(for: appStore.adventureRoot, tabId: tabId)
            .environment(appStore.adventureRoot)
    }
}

struct NewAudioRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            AudioFactory.rootExtendedView(for: appStore.audioRoot, tabId: tabId)
                .environment(appStore.audioRoot)
    }
}

struct NewDiceRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            DiceFactory.rootExtendedView(for: appStore.diceRoot, tabId: tabId)
                .environment(appStore.diceRoot)
    }
}

struct NewMapRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            MapFactory.rootExtendedView(for: appStore.mapRoot, tabId: tabId)
                .environment(appStore.mapRoot)
    }
}

struct NewPdfRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            PdfFactory.rootExtendedView(for: appStore.pdfRoot, tabId: tabId)
                .environment(appStore.pdfRoot)
    }
}
struct NewPhotoRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            PhotoFactory.rootExtendedView(for: appStore.photoRoot, tabId: tabId)
                .environment(appStore.photoRoot)
    }
}

struct NewSpaceRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            SpaceFactory.rootView()
                .environment(appStore.spaceRoot)
    }
}

struct NewTableRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            TableFactory.rootExtendedView(for: appStore.tableRoot, tabId: tabId)
                .environment(appStore.tableRoot)
    }
}

struct NewValueRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            ValueFactory.rootExtendedView(for: appStore.valueRoot, tabId: tabId)
                .environment(appStore.valueRoot)
    }
}

struct NewWeatherRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool
    
    var body: some View {
            WeatherFactory.rootExtendedView(for: appStore.weatherRoot, tabId: tabId)
                .environment(appStore.weatherRoot)
    }
}
