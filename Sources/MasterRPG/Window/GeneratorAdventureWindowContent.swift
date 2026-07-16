// @copyright André Trettin

#if !os(tvOS)
import AdventureRPG
import CoreRPG
import RolePlayGameKit
import SwiftUI

struct GeneratorAdventureWindowContent: View {
    let appModel: AppModel
    let selection: WindowItemSelection?

    private var windowSelection: WindowItemSelection? {
        selection ?? appModel.adventureRoot.currentSelectedItemId.map { WindowItemSelection(itemId: $0) }
    }

    var body: some View {
        switch windowSelection {
        case .some(let windowSelection):
            appModel.adventureRoot.viewController.generatorView(root: appModel.adventureRoot, selection: windowSelection)
        case .none:
            ContentUnavailableView {
                Label {
                    Text("No Adventure Selected", bundle: .main)
                } icon: {
                    Image(systemName: NetworkModules.adventure.icon)
                }
            } description: {
                Text("Select an adventure before opening the AI Assistant.", bundle: .main)
            }
        }
    }
}

#Preview("No selected adventure") {
    GeneratorAdventureWindowContent(
        appModel: AppModel(),
        selection: nil
    )
}

#endif
