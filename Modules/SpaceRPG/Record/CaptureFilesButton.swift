/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import CoreRPG
import SwiftUI
import os

extension CaptureOverlayView {
    struct CaptureFilesButton: View {
        @Environment(AppDataModel.self) private var appModel
        @State private var showDocumentBrowser = false

        var body: some View {
            Button {
                Logger.scanner3D.log("Files button clicked!")
                showDocumentBrowser = true
            } label: {
                Label {
                    Text("Open Capture Files", bundle: .module)
                } icon: {
                    Image(systemName: "folder")
                }
                .labelStyle(.iconOnly)
                .imageScale(.large)
                .foregroundStyle(.white)
            }
            .frame(minWidth: 44, minHeight: 44)
            .padding(.bottom, 20)
            .padding(.horizontal, 10)
            .sheet(
                isPresented: $showDocumentBrowser,
                onDismiss: { showDocumentBrowser = false }
            ) {
                if let folderManager = appModel.scanFolderManager {
                    ManagedPresentationView {
                        DocumentBrowser(startingDir: folderManager.rootScanFolder)
                    }
                }
            }
        }
    }
}

#Preview {
    CaptureOverlayView.CaptureFilesButton()
        .environment(AppDataModel.instance)
        .padding()
        .background(.black)
}

#endif
