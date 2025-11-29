// @copyright André Trettin

#if os(macOS)

import AndrenalinKit
import RolePlayGameKit
import SwiftUI

struct LinkWindowCommandsView: View {
    var body: some View {
        Group {
            AltLinkWindowCommandView(title: NetworkModules.adventure.title, networkModule: .adventure, key: "1")
            AltLinkWindowCommandView(title: NetworkModules.value.title, networkModule: .value, key: "2")
            AltLinkWindowCommandView(title: NetworkModules.pdf.title, networkModule: .pdf, key: "3")
            AltLinkWindowCommandView(title: NetworkModules.table.title, networkModule: .table, key: "4")
        }
        AltLinkWindowCommandView(title: NetworkModules.map.title, networkModule: .map, key: "5")
        
        Group {
            AltLinkWindowCommandView(title: NetworkModules.audio.title, networkModule: .audio, key: "6")
            AltLinkWindowCommandView(title: NetworkModules.dice.title, networkModule: .dice, key: "7")
            AltLinkWindowCommandView(title: NetworkModules.photo.title, networkModule: .photo, key: "8")
            AltLinkWindowCommandView(title: NetworkModules.space.title, networkModule: .space, key: "9")
        }
        
        AltLinkWindowCommandView(title: NetworkModules.weather.title, networkModule: .weather, key: "0")
    }
}

#endif
