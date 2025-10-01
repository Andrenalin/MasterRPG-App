// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController: Sendable {
    @MainActor
    public func gameWindow<Content: View>(root: GameRootController, @ViewBuilder rootView: @escaping () -> Content) -> some View {
        GameRootView(root: root, rootView: rootView)
    }

    @MainActor
    public func gameTabItem(root: GameRootController) -> some View {
        GameRootTabItemView(root: root)
    }

    @MainActor
    public func logWindow(root: GameRootController) -> some View {
        LogMessageList(logController: root.logGameController)
    }

//    @MainActor @ViewBuilder
//    func selectedCharacterGameMasterView(with id: UUID?, isGameMaster: Bool = false) -> some View {
//        if let id = root.valueRoot.linkController.validate(id: id, isCharacter: !isGameMaster, isGameMaster: isGameMaster) {
//            root.valueRoot.viewController.viewMinimum(with: id)
//        } else {
//            ProgressView().progressViewStyle(.circular)
//        }
//    }
//
//    @MainActor @ViewBuilder
//    func selectedAdventureView(with id: UUID?) -> some View {
//        if let id, root.adventureRoot.linkController.validateLink(itemId: id) == true {
//            root.adventureRoot.viewController.viewMinimum(with: id)
//        } else {
//            ProgressView().progressViewStyle(.circular)
//        }
//    }
}
