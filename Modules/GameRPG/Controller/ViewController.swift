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

    @MainActor @ViewBuilder
    func selectedCharacterGameMasterView(with id: UUID?, isGameMaster: Bool = false) -> some View {
        if let id = root.characterRoot.linkController.validate(id: id, isCharacter: !isGameMaster, isGameMaster: isGameMaster) {
            root.characterRoot.viewController.viewMinimum(root: root.characterRoot, with: id)
        } else {
            ProgressView().progressViewStyle(.circular)
        }
    }

    @MainActor @ViewBuilder
    func selectedAdventureView(with id: UUID?) -> some View {
        if let id, root.adventureRoot.linkController.validateLink(itemId: id) == true {
            root.adventureRoot.viewController.viewMinimum(root: root.adventureRoot, with: id)
        } else {
            ProgressView().progressViewStyle(.circular)
        }
    }
}
