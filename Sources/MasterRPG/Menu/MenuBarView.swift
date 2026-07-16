// @copyright André Trettin

import AudioRPG
import RolePlayGameKit
import SwiftUI

struct MenuBarView: View {
    let appModel: AppModel

    var body: some View {
        DataBaseAppStoreAvailable(appModel: appModel) { appModel in
            VStack {
                Text("Music in MasterRPG", bundle: .main)
                    .accessibilityAddTraits(.isHeader)
                
                Divider()
                
                appModel.audioRoot.viewController.viewAudioPlayer(root: appModel.audioRoot, with: nil)
                
            }
            .padding()
            .environment(appModel.audioRoot)
        }
    }
}


#Preview {
    MenuBarView(appModel: .preview)
}
