// @copyright André Trettin

#if os(macOS)
import CharacterRPG
import CoreRPG
import SwiftUI

struct BattleRoundCharacterInspectorView: View {
    let controller: BattleRoundController
    @Bindable var screenModel: BattleRoundScreenModel

    var body: some View {
        // `.inspector` is the same bare, non-selecting browsing mode
        // `EditorLinkView` uses for its Character slot: rows stay draggable
        // (`InspectorRowView` applies `.draggable` unconditionally) but tap
        // no longer assigns anything — dropping onto a combatant card is the
        // only way to assign a Character or value from here.
        controller.root.characterRoot.viewController.linkListView(
            type: .inspector,
            itemSelectionModel: screenModel.pendingValueSelection == nil
                ? screenModel.selectedCharacter
                : screenModel.selectedValue
        )
    }
}
#endif
