// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGAdventures
import RPGAudios
import RPGPdfs
import RPGPhotos
import RPGSpaces

public struct SettingsView: View {
    public init(store: AppStore) {
        self.store = store
    }
    
    let store: AppStore

    @Environment(\.navigator) private var navigator

    public var body: some View {
        AndrenalinKit.SettingsView(store: store.adventureRoot, exportController: store.adventureRoot.exportControllable, importController: store.adventureRoot.importControllable, audioFileStore: store.audioRoot.fileUrlDataController!, pdfFileStore: store.pdfRoot.fileUrlDataController!, photoFileStore: store.photoRoot.fileUrlDataController!, spaceFileStore: store.spaceRoot.fileUrlDataController!) {

//            SectionGroupEditorView {
//                InAppView(inAppController: store.inAppController)
//            } header: {
//                Text("In App Purchase")
//            }

            SectionGroupEditorView {
                Button {
                    Task {
                        await store.audioRoot.checkFolders()
                        await store.pdfRoot.checkFolders()
                        await store.photoRoot.checkFolders()
                        await store.spaceRoot.checkFolders()
                    }
                } label: {
                    Label("Create Folders", systemImage: "folder")
                }
            } header: {
                Text("Data Checks")
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
                Text("Import Prebundled Examples")
            } footer: {
                Text("Explanation data packages to see how the app works. It explain with real data how to use and add data.")
            }            

            SectionGroupEditorView {
                Text("Use the Free Support [Page](https://github.com/Andrenalin/MasterRPG)")
            } header: {
                Text("Download free game bundles")
            } footer: {
                Text("These are free packages ready to use. They will add tables with rules, photos, characters and adventures for a certain rule system.")
            }
            
            SectionGroupEditorView {
                Text(store.rpgSpotlightIndexer?.model.message ?? "Not yet finished")
            } header: {
                Text("Spotlight Indexer Message")
            }
        }
        .environment(store.settingsModel)
    }
}

#Preview {
    SettingsView(store: .preview)
}
