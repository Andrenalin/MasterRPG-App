// @copyright André Trettin

import CoreRPG
import SwiftUI
import AdventureRPG
import AudioRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import MapRPG
import CharacterRPG
import WeatherRPG
import DiceRPG

public struct SettingsView: View {
    public init(store: AppModel) {
        self.store = store
    }
    
    let store: AppModel

    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        CoreRPG.SettingsView(store: store.adventureRoot, exportController: store.adventureRoot.exportControllable, importController: store.adventureRoot.importControllable) {

            SectionGroupEditorView {
                Button {
                    navigator.navigate(to: SettingsRoute.exportData, method: .managedSheet)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button {
                    navigator.navigate(to: SettingsRoute.importData, method: .managedSheet)
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

            } header: {
                Text("Manage Data", bundle: .module)
            }
            

            SectionGroupEditorView {
                Button {
                    navigator.navigate(to: SettingsRoute.validate, method: .managedSheet)
                } label: {
                    Label("Validate Folders", systemImage: "folder")
                }
            } header: {
                Text("Data Checks", bundle: .module)
            }

            SectionGroupEditorView {
                Text(store.rpgSpotlightIndexer?.model.message ?? "Not yet finished")
                
                if let model = store.coreDataInitModel {
                    CloudKitSyncStatusView(syncState: model.cloudKitSyncState, lastSync: model.lastSuccessfulSync)
                }
            } header: {
                Text("iCloud Sync Status", bundle: .module)
            }
            
            //            SectionGroupEditorView {
            //                InAppView(inAppController: store.inAppController)
            //            } header: {
            //                Text("In App Purchase")
            //            }


        }
        .environment(store.settingsModel)
    }
}

#Preview {
    SettingsView(store: .preview)
}
