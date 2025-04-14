// @copyright André Trettin

import SwiftUI

struct FileStorageEditor: View {
    let module: NetworkModules
    let fileStore: FileUrlDataController
    
    let locations: [FileLocation] = [.local, .appCloud, .icloud]
    
    @State private var alertMessage = ""
    @State private var showFolderSelector = false
    @State private var showValidationAlert = false
    
    @State private var showFiles = false
    @State private var showFolder = false
    
    var body: some View {
#if os(macOS)
        HStack {
            fileActionBarView
        }
#else
        fileActionBarView
#endif
        
        if fileStore.model.defaultLoaction == .icloud && fileStore.model.defaultCloudPath == nil {
            Text("Warnung: The default Accessible \(String(localized: module.localizedTitle)) Folder path is not set. If you choose default location iCloud, please provide a default path to your iCloud path, where the files can be written. The app will fallback to AppCloud if it cannot write into the given path.", bundle: .module)
                .font(.headline)
        }
    }
    
    @ViewBuilder
    private var fileActionBarView: some View {
        @Bindable var model = fileStore.model
        
        Picker(selection: $model.defaultLoaction) {
            ForEach(locations) {
                Text($0.text)
                    .tag($0)
            }
        } label: {
            Label(String(localized: module.localizedTitle), systemImage: module.icon)
        }
        
        Button {
            showFolder.toggle()
        } label: {
            Label("\(String(localized: module.localizedTitle)) Folder Management", systemImage: "folder")
        }
        .sizedSheet(isPresented: $showFolder, idealSize: CGSize(width: 600, height: 800)) {
            FolderSettingsEditor(fileStore: fileStore)
        }
        
        Button {
            showFiles.toggle()
        } label: {
            Label("\(String(localized: module.localizedTitle)) File Management", systemImage: "doc")
        }
        .sizedSheet(isPresented: $showFiles) {
            SelectFolderSettingsEditor(fileStore: fileStore)
        }
    }
}

#Preview {
    FileStorageEditor(module: .audio, fileStore: .empty())
}
