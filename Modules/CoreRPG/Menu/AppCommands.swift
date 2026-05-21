// @copyright André Trettin

import SwiftUI

#if !os(tvOS)

public struct AltLinkWindowCommandView: View {
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

    @Environment(ScenesManager.self) private var sceneManager

    public var body: some View {
        Button {
            sceneManager.openWindow(SceneId(rawValue: windowId))
        } label: {
            Label(titleWindow(), systemImage: icon)
        }
        .keyboardShortcut(key, modifiers: [.command, .option, .shift])
    }
    
    func titleWindow() -> String {
        let newTitle = String(localized: "New", bundle: .module).localizedString
        return newTitle + " " + title
    }
}

#endif
