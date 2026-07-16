// @copyright André Trettin

import SwiftUI

@MainActor
public protocol StoreManiplable: Sendable {
    func resetData() async
    func validate()
}

public struct SettingsView<Store, ImportContent: View>: View where Store: StoreManiplable {
    public init(store: Store, exportController: any ExportControllable, importController: any ImportControllable, @ViewBuilder importContent: () -> ImportContent) {
        self.store = store
        self.exportController = exportController
        self.importController = importController
        self.importContentView = importContent()
    }
    
    let store: Store
    let exportController: any ExportControllable
    let importController: any ImportControllable        
    let importContentView: ImportContent
    
    @State private var showResetAlert = false
    
    public var body: some View {
        List {
#if os(iOS)
            ColorSchemeSettingsView()
#endif
                        
            importContentView
                        
            StorageOptionEditor()
            
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

@MainActor
final class SettingsPreviewStore: StoreManiplable {
    func resetData() async {}
    func validate() {}
}

#Preview {
    SettingsView(
        store: SettingsPreviewStore(),
        exportController: FakeExportController.fake,
        importController: FakeImportController.fake
    ) {
        Section {
            Text(verbatim: "Import data from a file")
        } header: {
            Text(verbatim: "Import")
        }
    }
}
