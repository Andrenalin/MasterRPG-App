// @copyright André Trettin

#if os(macOS)

import AndrenalinKit
import RoleGameKit
import SwiftUI

struct LinkWindowCommandsView: View {
    var body: some View {
        Group {
            LinkWindowCommandView(title: NetworkModules.adventure.title, networkModule: .adventure, key: "1")
            LinkWindowCommandView(title: NetworkModules.value.title, networkModule: .value, key: "2")
            LinkWindowCommandView(title: NetworkModules.pdf.title, networkModule: .pdf, key: "3")
            LinkWindowCommandView(title: NetworkModules.table.title, networkModule: .table, key: "4")
        }
        LinkWindowCommandView(title: NetworkModules.map.title, networkModule: .map, key: "5")
        
        Group {
            LinkWindowCommandView(title: NetworkModules.audio.title, networkModule: .audio, key: "6")
            LinkWindowCommandView(title: NetworkModules.dice.title, networkModule: .dice, key: "7")
            LinkWindowCommandView(title: NetworkModules.photo.title, networkModule: .photo, key: "8")
            LinkWindowCommandView(title: NetworkModules.space.title, networkModule: .space, key: "9")
        }
        
        LinkWindowCommandView(title: NetworkModules.weather.title, networkModule: .weather, key: "0")
    }
}

#endif
