//
//  MenuMainCommand.swift
//  MasterRPG
//
//  Created by Andre Trettin on 6/10/2568 BE.
//


// @copyright André Trettin

import RolePlayGameKit
import SwiftUI

struct MenuMainCommand: Commands {
    let appModel: AppModel
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
