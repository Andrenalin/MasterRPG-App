// @copyright André Trettin

#if !os(tvOS)

import RoleGameKit
import SwiftUI

struct OldMenuMainCommand: Commands {
    let appStore: AppStore
    var body: some Commands {
#if os(macOS)
        OldAboutPanelCommand(title: "Master RPG", credits: "Many thanks to my long running test party: Karsten, Roman and Timo.")
        ImportFromDevicesCommands()
#endif
        SidebarCommands()
        TextEditingCommands()
        TextFormattingCommands()
        
        OldMenuCommandList(appStore: appStore)
    }
}

#endif
