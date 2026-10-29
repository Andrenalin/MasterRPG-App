// @copyright André Trettin

import SwiftUI

/// Opens the sync of the module's items with its iCloud folder. Only for modules that
/// keep their files in iCloud, and not while a game runs: the sync changes the permanent library.
struct CloudFolderScanButton: View {
    let root: any ItemRootControllable

    var body: some View {
        if root.itemControllable.fileUrlDataController != nil {
            Button {
                root.navigationModel.triggerCloudScan = true
            } label: {
                Label {
                    Text("Sync with iCloud…", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                }
            }
            .disabled(root.itemControllable.itemDataModel.isGameMode)
        }
    }
}

#Preview { CloudFolderScanButton(root: ItemRootController.fake) }
