// @copyright André Trettin

import SwiftUI

#if !os(tvOS)

public struct LinkWindowCommandView: View {
    public init(networkModule: NetworkModules, scenesManager: ScenesManager, key: AKKeyEquivalent) {
        self.title = String(localized: "\(networkModule.title) Link", bundle: .module)
        self.icon = networkModule.icon
        self.windowId = networkModule.linkWindowId
        self.scenesManager = scenesManager
        self.key = key
    }

    let title: String
    let icon: String
    let windowId: String
    let scenesManager: ScenesManager
    let key: AKKeyEquivalent

    public var body: some View {
        Button {
            scenesManager.openWindow(SceneId(rawValue: windowId))
        } label: {
            Label(title, systemImage: icon)
        }
        .keyboardShortcut(key, modifiers: [.command, .option, .shift])
    }
}

#endif

#if !os(tvOS)
#Preview {
    LinkWindowCommandView(networkModule: .adventure, scenesManager: ScenesManager(), key: "l")
}
#endif
