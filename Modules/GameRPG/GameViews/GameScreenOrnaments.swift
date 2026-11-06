// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import DiceRPG
import SwiftUI

extension View {
    /// The game screen's visionOS ornaments: close button, dice, game menu and the role's side
    /// menu. The game-master and player screens had identical copies. See CODE_AUDIT_19 §9.19.
    func gameScreenOrnaments<SideMenu: View>(
        root: GameRoot,
        gameScreenModel: GameScreenModel,
        diceShowOptionModel: DiceDisplayModel,
        playerController: PlayerController?,
        isMaster: Bool,
        @ViewBuilder sideMenu: () -> SideMenu
    ) -> some View {
        self
            .gameImmersiveSpaceSync(root: root)
            .ornament(attachmentAnchor: .scene(.topLeading), contentAlignment: .bottomLeading) {
                GameOrnamentCloseButton()
                    .environment(gameScreenModel)
            }
            .ornament(attachmentAnchor: .scene(.topLeading), contentAlignment: .topTrailing) {
                root.diceRoot.viewController.dicePlayerView(root: root.diceRoot)
                    .environment(diceShowOptionModel)
            }
            .ornament(attachmentAnchor: .scene(.topTrailing), contentAlignment: .bottomTrailing) {
                OverlayGameMenu(root: root, playerController: playerController, isMaster: isMaster)
                    .environment(diceShowOptionModel)
                    .environment(gameScreenModel)
                    .padding(.bottom, 12)
            }
            .ornament(attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
                VStack(alignment: .leading) {
                    sideMenu()
                        .environment(gameScreenModel)
                    // Below the side menu, in the same ornament, so they never overlap. Its
                    // toggle button is in the bottom trailing ornament, after the dice result.
                    if root.offersQuickDice(isMaster: isMaster), gameScreenModel.showQuickDice {
                        QuickDiceOverlay(root: root)
                            .environment(gameScreenModel)
                    }
                }
                .padding(12)
            }
            .ornament(attachmentAnchor: .scene(.bottomLeading), contentAlignment: .topLeading) {
                root.diceRoot.viewController.diceActionBarView(root: root.diceRoot)
                    .padding(.top, 12)
                    .environment(diceShowOptionModel)
            }
            .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
                root.diceRoot.viewController.diceRollView(root: root.diceRoot)
                    .padding(.top, 56)
                    .environment(diceShowOptionModel)
            }
            .ornament(attachmentAnchor: .scene(.bottomTrailing), contentAlignment: .topTrailing) {
                HStack(alignment: .top) {
                    root.diceRoot.viewController.diceResultView(root: root.diceRoot)
                        .environment(diceShowOptionModel)

                    if root.offersQuickDice(isMaster: isMaster) {
                        QuickDiceToggleField()
                            .environment(gameScreenModel)
                    }
                }
                .padding(.top, 12)
            }
    }
}
#endif
