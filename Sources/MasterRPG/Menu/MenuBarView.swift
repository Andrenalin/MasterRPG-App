// @copyright André Trettin

#if os(macOS)
import AudioRPG
import RolePlayGameKit
import SwiftUI

struct MenuBarView: View {
    let appModel: AppModel

    var body: some View {
        DataBaseAppStoreAvailable(appModel: appModel) { appModel in
            VStack {
                Text("Music in MasterRPG", bundle: .main)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                Divider()

                appModel.audioRoot.viewController.viewMenuBarAudioPlayer(root: appModel.audioRoot)
            }
            .padding()
            .environment(appModel.audioRoot)
        }
    }
}


#Preview {
    MenuBarView(appModel: .preview)
}
#endif
