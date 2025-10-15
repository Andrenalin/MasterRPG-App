// @copyright André Trettin

import CoreRPG
import Foundation

import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

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

    @State private var cacheModel = CacheItemListModel()
    @State private var deviceRotationModel = DeviceRotationModel()
    @State private var tabTitleModel = TabTitleModel()

    @Environment(\.modelContext) private var modelContext

    var body: some View {
            if isExtended {
                AdventureFactory.rootExtendedView(for: appStore.adventureRoot, tabId: tabId)
                    .environment(appStore.adventureRoot)
            } else {
                AdventureFactory.rootView(for: appStore.adventureRoot, tabId: tabId)
                    .environment(appStore.adventureRoot)
            }
    }
}

struct NewAudioRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool

    @State private var cacheModel = CacheItemListModel()
    @State private var deviceRotationModel = DeviceRotationModel()
    @State private var tabTitleModel = TabTitleModel()

    @Environment(\.modelContext) private var modelContext

    var body: some View {
            if isExtended {
                AudioFactory.rootExtendedView(for: appStore.audioRoot, tabId: tabId)
                    .environment(appStore.audioRoot)
            } else {
                AudioFactory.rootView(for: appStore.audioRoot, tabId: tabId)
                    .environment(appStore.audioRoot)
            }
    }
}

struct NewDiceRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool

    @State private var cacheModel = CacheItemListModel()
    @State private var deviceRotationModel = DeviceRotationModel()
    @State private var tabTitleModel = TabTitleModel()

    @Environment(\.modelContext) private var modelContext

    var body: some View {
            if isExtended {
                DiceFactory.rootExtendedView(for: appStore.diceRoot, tabId: tabId)
                    .environment(appStore.diceRoot)
            } else {
                DiceFactory.rootView(for: appStore.diceRoot, tabId: tabId)
                    .environment(appStore.diceRoot)
            }
    }
}
struct NewMapRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool

    @State private var cacheModel = CacheItemListModel()
    @State private var deviceRotationModel = DeviceRotationModel()
    @State private var tabTitleModel = TabTitleModel()

    @Environment(\.modelContext) private var modelContext

    var body: some View {
            if isExtended {
                MapFactory.rootExtendedView(for: appStore.mapRoot, tabId: tabId)
                    .environment(appStore.mapRoot)
            } else {
                MapFactory.rootView(for: appStore.mapRoot, tabId: tabId)
                    .environment(appStore.mapRoot)
            }
    }
}
struct NewPdfRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool

    @State private var cacheModel = CacheItemListModel()
    @State private var deviceRotationModel = DeviceRotationModel()
    @State private var tabTitleModel = TabTitleModel()

    @Environment(\.modelContext) private var modelContext

    var body: some View {
            if isExtended {
                PdfFactory.rootExtendedView(for: appStore.pdfRoot, tabId: tabId)
                    .environment(appStore.pdfRoot)
            } else {
                PdfFactory.rootView(for: appStore.pdfRoot, tabId: tabId)
                    .environment(appStore.pdfRoot)
            }
    }
}
struct NewPhotoRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool

    @State private var cacheModel = CacheItemListModel()
    @State private var deviceRotationModel = DeviceRotationModel()
    @State private var tabTitleModel = TabTitleModel()

    @Environment(\.modelContext) private var modelContext

    var body: some View {
            if isExtended {
                PhotoFactory.rootExtendedView(for: appStore.photoRoot, tabId: tabId)
                    .environment(appStore.photoRoot)
            } else {
                PhotoFactory.rootView(for: appStore.photoRoot, tabId: tabId)
                    .environment(appStore.photoRoot)
            }
    }
}

struct NewSpaceRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool

    @State private var cacheModel = CacheItemListModel()
    @State private var deviceRotationModel = DeviceRotationModel()
    @State private var tabTitleModel = TabTitleModel()

    @Environment(\.modelContext) private var modelContext

    var body: some View {
            if isExtended {
                SpaceFactory.rootExtendedView(for: appStore.spaceRoot, tabId: tabId)
                    .environment(appStore.spaceRoot)
            } else {
                SpaceFactory.rootView(for: appStore.spaceRoot, tabId: tabId)
                    .environment(appStore.spaceRoot)
            }
    }
}

struct NewTableRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool

    @State private var cacheModel = CacheItemListModel()
    @State private var deviceRotationModel = DeviceRotationModel()
    @State private var tabTitleModel = TabTitleModel()

    @Environment(\.modelContext) private var modelContext

    var body: some View {
            if isExtended {
                TableFactory.rootExtendedView(for: appStore.tableRoot, tabId: tabId)
                    .environment(appStore.tableRoot)
            } else {
                TableFactory.rootView(for: appStore.tableRoot, tabId: tabId)
                    .environment(appStore.tableRoot)
            }
    }
}

struct NewValueRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool

    @State private var cacheModel = CacheItemListModel()
    @State private var deviceRotationModel = DeviceRotationModel()
    @State private var tabTitleModel = TabTitleModel()

    @Environment(\.modelContext) private var modelContext

    var body: some View {
            if isExtended {
                ValueFactory.rootExtendedView(for: appStore.valueRoot, tabId: tabId)
                    .environment(appStore.valueRoot)
            } else {
                ValueFactory.rootView(for: appStore.valueRoot, tabId: tabId)
                    .environment(appStore.valueRoot)
            }
    }
}

struct NewWeatherRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool

    @State private var cacheModel = CacheItemListModel()
    @State private var deviceRotationModel = DeviceRotationModel()
    @State private var tabTitleModel = TabTitleModel()

    @Environment(\.modelContext) private var modelContext

    var body: some View {
            if isExtended {
                WeatherFactory.rootExtendedView(for: appStore.weatherRoot, tabId: tabId)
                    .environment(appStore.weatherRoot)
            } else {
                WeatherFactory.rootView(for: appStore.weatherRoot, tabId: tabId)
                    .environment(appStore.weatherRoot)
            }
    }
}
