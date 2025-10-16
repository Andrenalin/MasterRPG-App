// @copyright André Trettin

import SwiftUI

#if !os(tvOS)

public struct LinkWindowCommandView: View {
    public init(title: String, networkModule: NetworkModules, key: AKKeyEquivalent) {
        self.title = title
        self.icon = networkModule.icon
        self.windowId = networkModule.linkAltWindowId
        self.key = key
    }

    public init(title: String, icon: String, windowId: String, key: AKKeyEquivalent) {
        self.title = title
        self.icon = icon
        self.windowId = windowId
        self.key = key
    }

    let title: String
    let icon: String
    let windowId: String
    let key: AKKeyEquivalent

    @Environment(\.openWindow) private var openWindow
    
    public var body: some View {
        Button {
            openWindow(id: windowId)
        } label: {
            Label(titleWindow(), systemImage: icon)
        }
        .keyboardShortcut(key, modifiers: [.command, .option, .shift])
    }
    
    func titleWindow() -> String {
        let newTitle = String(localized: "New").localizedString
        return newTitle + " " + title
    }
}

#endif
