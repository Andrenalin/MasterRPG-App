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
        CoreRPG.SettingsView(store: store.adventureRoot, exportController: store.adventureRoot.exportControllable, importController: store.adventureRoot.importControllable, audioFileStore: store.audioRoot.fileUrlDataController!, pdfFileStore: store.pdfRoot.fileUrlDataController!, photoFileStore: store.photoRoot.fileUrlDataController!, spaceFileStore: store.spaceRoot.fileUrlDataController!) {

//            SectionGroupEditorView {
//                InAppView(inAppController: store.inAppController)
//            } header: {
//                Text("In App Purchase")
//            }

            SectionGroupEditorView {
                Button {
                    navigator.navigate(to: ValidateRoute.validate, method: .managedSheet)
                } label: {
                    Label("Create Folders", systemImage: "folder")
                }
            } header: {
                Text("Data Checks", bundle: .module)
            }

            SectionGroupEditorView {
                Button {
                    store.installExampleData()
                } label: {
                    Label("Import Explanation English Data", systemImage: "square.and.arrow.down")
                }

                Button {
                    store.installExampleData(isGerman: true)
                } label: {
                    Label("Import Explanation German Data", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Import Prebundled Examples", bundle: .module)
            } footer: {
                Text("Explanation data packages to see how the app works. It explain with real data how to use and add data.", bundle: .module)
            }

            SectionGroupEditorView {
                Text("Use the Free Support [Page](https://github.com/Andrenalin/MasterRPG)", bundle: .module)
            } header: {
                Text("Download free game bundles", bundle: .module)
            } footer: {
                Text("These are free packages ready to use. They will add tables with rules, photos, characters and adventures for a certain rule system.", bundle: .module)
            }

            SectionGroupEditorView {
                Text(store.rpgSpotlightIndexer?.model.message ?? "Not yet finished")
                
                if let model = store.coreDataInitModel {
                    CloudKitSyncStatusView(syncState: model.cloudKitSyncState, lastSync: model.lastSuccessfulSync)
                }
            } header: {
                Text("iCloud Sync Status", bundle: .module)
            }
        }
        .environment(store.settingsModel)
    }
}

#Preview {
    SettingsView(store: .preview)
}
