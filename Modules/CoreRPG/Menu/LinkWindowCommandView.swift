// @copyright André Trettin

import SwiftUI

#if !os(tvOS)

public struct LinkWindowCommandView: View {
    public init(networkModule: NetworkModules, scenesManager: ScenesManager, key: AKKeyEquivalent, isAlt: Bool = false) {
        self.title = String(localized: "\(networkModule.title) Link", bundle: .module)
        self.icon = networkModule.icon
        self.windowId = isAlt ? networkModule.linkAltWindowId : networkModule.linkWindowId
        self.scenesManager = scenesManager
        self.key = key
        self.isAlt = isAlt
    }

    let title: String
    let icon: String
    let windowId: String
    let scenesManager: ScenesManager
    let key: AKKeyEquivalent
    let isAlt: Bool

    public var body: some View {
        Button {
            scenesManager.openWindow(SceneId(rawValue: windowId))
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
        return String(localized: "New \(title)", bundle: .module)
    }
}

#endif

#if !os(tvOS)
#Preview {
    LinkWindowCommandView(networkModule: .adventure, scenesManager: ScenesManager(), key: "l")
}
#endif
