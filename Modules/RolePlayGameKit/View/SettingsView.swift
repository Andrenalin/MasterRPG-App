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
                    Label { Text("Export", bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") }
                }

                Button {
                    navigator.navigate(to: SettingsRoute.importData, method: .managedCover)
                } label: {
                    Label { Text("Import", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
                }

            } header: {
                Text("Manage Data", bundle: .module)
            }
            

            SectionGroupEditorView {
                Button {
                    navigator.navigate(to: SettingsRoute.validate, method: .managedSheet)
                } label: {
                    Label { Text("Validate Folders", bundle: .module) } icon: { Image(systemName: "folder") }
                }
            } header: {
                Text("Data Checks", bundle: .module)
            }

            SectionGroupEditorView {
                if let message = store.rpgSpotlightIndexer?.model.message {
                    Text(verbatim: message)
                } else {
                    Text("Not yet finished", bundle: .module)
                }
                
                if let model = store.coreDataInitModel {
                    CloudKitSyncStatusView(syncState: model.cloudKitSyncState, lastSync: model.lastSuccessfulSync)
                }
            } header: {
                Text("iCloud Sync Status", bundle: .module)
            }

            SectionGroupEditorView {
                Button {
                    MasterRPGTips.reset()
                } label: {
                    Label {
                        Text("Show Tips Again", bundle: .module)
                    } icon: {
                        Image(systemName: "lightbulb")
                    }
                }
            } header: {
                Text("Tips", bundle: .module)
            } footer: {
                Text("Restores in-app guidance for creating, organizing, linking, and playing.", bundle: .module)
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
