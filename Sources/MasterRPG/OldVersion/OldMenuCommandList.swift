// @copyright André Trettin

#if !os(tvOS)

import RPGAdventures
import RPGDie
import RoleGameKit
import RPGAudios
import RPGGame
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGValues
import SwiftUI
import RPGWeathers

struct OldMenuCommandList: Commands {
    let appStore: AppStore
    
    var body: some Commands {
        if appStore.hasDatabase {
            Group {
                AdventureCommands(root: appStore.adventureRoot)
                ValueCommands(root: appStore.valueRoot)
                PdfCommands(root: appStore.pdfRoot)
                TableCommands(root: appStore.tableRoot)
            }

            MapCommands(root: appStore.mapRoot)

            Group {
                AudioCommands(root: appStore.audioRoot)
                DiceCommands(root: appStore.diceRoot)
                PhotoCommands(root: appStore.photoRoot)
                SpaceCommands(root: appStore.spaceRoot)
            }

            WeatherCommands(root: appStore.weatherRoot)
        }
    }
}

#endif
