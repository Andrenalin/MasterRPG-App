// @copyright André Trettin

import SwiftUI

#if !os(tvOS)

public struct LinkWindowCommandView: View {
    public init(networkModule: NetworkModules, scenesManager: ScenesManager, key: AKKeyEquivalent, isAlt: Bool = false) {
        self.title = "\(networkModule.title) Link"
        self.icon = networkModule.icon
        self.windowId = isAlt ? networkModule.linkAltWindowId : networkModule.linkWindowId
        self.sceneManager = scenesManager
        self.key = key
        self.isAlt = isAlt
    }

    let title: String
    let icon: String
    let windowId: String
    let sceneManager: ScenesManager
    let key: AKKeyEquivalent
    let isAlt: Bool

    public var body: some View {
        Button {
            sceneManager.openWindow(SceneId(rawValue: windowId))
        } label: {
            Label(titleWindow, systemImage: icon)
        }
        .keyboardShortcut(key, modifiers: [.command, .option, .shift])
    }
    
    var modifiers: EventModifiers {
        isAlt ? [.command, .option, .shift] : [.command, .option]
    }
    
    var titleWindow: String {
        guard isAlt else { return title }
        let newTitle = String(localized: "New", bundle: .module).localizedString
        return newTitle + " " + title
    }
}

#endif
