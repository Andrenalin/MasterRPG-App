// @copyright André Trettin

import SwiftUI

public protocol StoreManiplable: Sendable {
    func resetData() async
    func validate()
}

public struct SettingsView<Store, ImportContent: View>: View where Store: StoreManiplable {
    public init(store: Store, exportController: any ExportControllable, importController: any ImportControllable, audioFileStore: FileUrlDataController, pdfFileStore: FileUrlDataController, photoFileStore: FileUrlDataController, spaceFileStore: FileUrlDataController, @ViewBuilder importContent: () -> ImportContent) {
        self.store = store
        self.exportController = exportController
        self.importController = importController
        self.audioFileStore = audioFileStore
        self.pdfFileStore = pdfFileStore
        self.photoFileStore = photoFileStore
        self.spaceFileStore = spaceFileStore
        self.importContentView = importContent()
    }
    
    let store: Store
    let exportController: any ExportControllable
    let importController: any ImportControllable
    
    let audioFileStore: FileUrlDataController
    let pdfFileStore: FileUrlDataController
    let photoFileStore: FileUrlDataController
    let spaceFileStore: FileUrlDataController
    
    let importContentView: ImportContent
    
    @State private var showResetAlert = false
    
    public var body: some View {
        List {
#if os(iOS)
            ColorSchemeSettingsView()
#endif
            
            SectionGroupEditorView {
                ExportDataModels(exportController: exportController) {
                    let url = URL.cachesDirectory.appending(path: "Export.gmz")
                    let exportedIds = exportController.exportingAll()
                    return exportController.createExport(itemIds: exportedIds, into: url)
                }
                ImportDataModels(importController: importController) {
                }
                
#if os(macOS)
                Divider()
#endif
                
                ImportDataModels(importController: importController, overwrite: true) {
                }
                
            } header: {
                Text("Export & Import from files", bundle: .module)
            } footer: {
                Text("Import GMZ data files you got from friends or others", bundle: .module)
            }
            
            importContentView
            
            SectionGroupEditorView {
                Button {
                    store.validate()
                } label: {
                    Label("Validate Links", systemImage: "checkmark.shield")
                }
            } header: {
                Text("Validate Data", bundle: .module)
            } footer: {
                Text("Validate the links", bundle: .module)
            }
            
            StorageOptionEditor(audioFileStore: audioFileStore, pdfFileStore: pdfFileStore, photoFileStore: photoFileStore, spaceFileStore: spaceFileStore)
            
            SectionGroupEditorView {
                Button(role: .destructive) {
                    withAnimation { showResetAlert.toggle() }
                } label: {
                    Label {
                        Text("Reset Data", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark.circle")
                    }
                }
                .alert(Text("Really Reset?", bundle: .module), isPresented: $showResetAlert) {
                    Button(role: .cancel) {
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                    Button(role: .destructive) {
                        let localStore = store
                        Task {
                            await localStore.resetData()
                        }
                    } label: {
                        Text("Reset", bundle: .module)
                    }
                } message: {
                    Text("Becareful this removes all data from the database, all files in local and appCloud storage associated with the database. Files in other or iCloud will not be touched.", bundle: .module)
                }
            } header: {
                Text("Reset", bundle: .module)
            } footer: {
                Text("Becareful this removes all data and resets the database.", bundle: .module)
            }
        }
        .navigationTitle(Text("Settings", bundle: .module))
    }
}
