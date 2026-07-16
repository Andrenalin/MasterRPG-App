// @copyright André Trettin

import SwiftUI

public struct AltOpenWindowButton: View {
    public init(module: NetworkModules) {
        self.module = module
    }

    let module: NetworkModules

    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        if supportsMultipleWindows {
            OptionKeyPressedButton { isPressed in
#if !os(tvOS)
                withAnimation(reduceMotion ? nil : .default) {
                    if isPressed {
                        scenesManager.openWindow(SceneId(rawValue: module.linkAltWindowId))
                    } else {
                        scenesManager.openWindow(SceneId(rawValue: module.linkWindowId))
                    }
                }
#endif
            } label: { isPressed in
                Label {
                    Text("Open \(module.title) Window", bundle: .module)
                } icon: {
                    Image(systemName: module.icon)
                        .overlay(alignment: .top) {
                            Image(systemName: "plus")
                                .imageScale(.small)
                                .foregroundStyle(.green)
                                .padding(2)
                                .background(.ultraThinMaterial, in: Circle())
                                .offset(x: 8, y: -8)
                                .opacity(isPressed ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                }
                .labelStyle(.iconOnly)
            }
        }
    }
}

#Preview {
    AltOpenWindowButton(module: .adventure)
        .environment(ScenesManager())
        .environment(OptionKeyDownModel())
}
