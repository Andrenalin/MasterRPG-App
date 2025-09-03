// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct SettingsView: View {
    public init(model: AppModel) {
        self.model = model
    }
    
    let model: AppModel

    @Environment(\.navigator) private var navigator

    public var body: some View {
        NavigationStack {
            List {
                ColorSchemeSettingsView()

                //            SectionGroupEditorView {
                //                InAppView(inAppController: store.inAppController)
                //            } header: {
                //                Text("In App Purchase")
                //            }

                SectionGroupEditorView {
//                    ExportDataModels(exportController: exportController) {
//                        let url = URL.cachesDirectory.appending(path: "Export.gmz")
//                        let exportedIds = exportController.exportingAll()
//                        return exportController.createExport(itemIds: exportedIds, into: url)
//                    }
//                    ImportDataModels(importController: importController) {
//                    }
//
//#if os(macOS)
//                    Divider()
//#endif
//
//                    ImportDataModels(importController: importController, overwrite: true) {
//                    }

                } header: {
                    Text("Export & Import from files", bundle: .module)
                } footer: {
                    Text("Import GMZ data files you got from friends or others", bundle: .module)
                }

                SectionGroupEditorView {
                    Button {
                        model.installExampleData()
                    } label: {
                        Label("Import Explanation English Data", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        model.installExampleData(isGerman: true)
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
        }
        .environment(model.settingsModel)
    }
}

#Preview {
    SettingsView(model: AppModel())
}
