// @copyright André Trettin

import SwiftUI

public protocol FileAccessible {
    func validateFiles() async -> Bool
    func validateFiles(root: URL) async -> Int
}

public struct FileAccessSettingsEditor: View {
    public init(store: FileUrlDataController) {
        self.store = store
    }

    let store: FileUrlDataController

    @State private var showSpinner = false
    @State private var showFolderPanel = false
    @State private var showValidationAlert = false
    @State private var alertMessage = ""

    @State private var filesChecked = false

    public var body: some View {
        Button {
            showSpinner = true
            Task {
                let valid = await store.validateFiles()
                Task { @MainActor in
                    showFolderPanel = !valid
                    filesChecked = valid
                    try await Task.sleep(for: .seconds(0.5))
                    showSpinner = false
                }
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .opacity(showSpinner ? 0 : 1)
                    .imageScale(.large)
                    .overlay {
                        ProgressView()
                            .opacity(showSpinner ? 1 : 0)
                    }

                Text("Validate Files", bundle: .module)
                
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.green)
                    .symbolEffect(.disappear, isActive: !filesChecked)
            }
            .animation(.default, value: showSpinner)
        }
        .disabled(showSpinner)
        .alert(alertMessage, isPresented: $showValidationAlert) {}
        #if !os(tvOS)
        .fileImporter(isPresented: $showFolderPanel, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            do {
                guard let selectedFolder: URL = try result.get().first else {
                    alertMessage = "Error during opening the validation folder"
                    showValidationAlert = true
                    return
                }
                Task {
                    showSpinner = true
                    let result = await store.validateFiles(root: selectedFolder)
                    Task { @MainActor in
                        filesChecked = true
                        showFolderPanel = false
                        try await Task.sleep(for: .seconds(0.5))
                        showSpinner = false
                        alertMessage = "There still \(result) files missing"
                        showValidationAlert = result > 0
                    }
                }
            } catch {
                alertMessage = error.localizedDescription
                showValidationAlert = true
            }
        }
        #endif
        .borderLessTVBottonStyle()
    }
}
