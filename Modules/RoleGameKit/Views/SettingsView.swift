// @copyright André Trettin

import AndrenalinKit
import SwiftUI

public struct SettingsView: View {
    public init(store: AppStore) {
        self.store = store
    }
    
    let store: AppStore

    @Environment(\.navigator) private var navigator

    public var body: some View {
        AndrenalinKit.SettingsView(store: store.adventureRoot, exportController: store.adventureRoot.exportControllable, importController: store.adventureRoot.importControllable, audioFileStore: store.audioRoot.fileUrlDataController, pdfFileStore: store.pdfRoot.fileUrlDataController, photoFileStore: store.photoRoot.fileUrlDataController, spaceFileStore: store.spaceRoot.fileUrlDataController) {
                    
//            SectionGroupEditorView {
//                InAppView(inAppController: store.inAppController)
//            } header: {
//                Text("In App Purchase")
//            }

            SectionGroupEditorView {
                Button("Convert / Move") {
                    Task {
                        try? await store.audioRoot.moveFiles()

                        try? await store.pdfRoot.moveFiles()

                        try? await store.photoRoot.moveFiles()

                        try? await store.spaceRoot.moveFiles()
                    }
                }
            } header: {
                Text("Spotlight Indexer Message")
            }

            SectionGroupEditorView {
                Text(store.rpgSpotlightIndexer?.model.message ?? "Not yet finished")
            } header: {
                Text("Spotlight Indexer Message")
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
        }
        .environment(store.settingsModel)
    }
}

#Preview {
    SettingsView(store: .preview)
}
