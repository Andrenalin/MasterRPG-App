// @copyright André Trettin

#if !os(tvOS)

import RoleGameKit
import SwiftUI

struct MenuMainCommand: Commands {
    let appModel: AppStore
    var body: some Commands {
        
#if os(macOS)
        AboutPanelCommand(title: "Master RPG", credits: "Many thanks to my long running test party: Karsten, Roman and Timo.")
        ImportFromDevicesCommands()
#endif
        SidebarCommands()
        TextEditingCommands()
        TextFormattingCommands()
        
        MenuCommandList(appModel: appModel)
    }
}

#endif
