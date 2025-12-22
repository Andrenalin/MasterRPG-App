// @copyright André Trettin

import CoreRPG
import SwiftUI
import CharacterRPG
import AdventureRPG

public struct ViewController {
    weak var root: GameRoot!
}

public extension ViewController {
    @MainActor
    func gameWindow<Content: View>(_ rootView: @escaping () -> Content) -> some View {
        GameRootView(root: root, rootView: rootView)
    }

    @MainActor
    func gameTabItem() -> some View {
        GameRootTabItemView(root: root)
    }

    @MainActor
    func logWindow() -> some View {
        LogMessageList(logController: root.logGameController)
    }
}
