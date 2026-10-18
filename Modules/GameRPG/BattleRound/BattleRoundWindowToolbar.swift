// @copyright André Trettin

#if os(macOS)
import MapRPG
import SwiftUI

/// The battle window's toolbar: the turn actions and the inspector toggle.
///
/// Window-level actions belong in the toolbar on macOS — they get keyboard
/// shortcuts and the system's own glass, outside the content's hosting view.
/// Inside the content, as glass buttons next to the cards' drag, drop and
/// menu gestures, they were part of the combination AppKit asserted on
/// before it stopped delivering clicks to the window.
struct BattleRoundWindowToolbar: ToolbarContent {
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    var body: some ToolbarContent {
        @Bindable var screenModel = screenModel
        let isRunning = controller.model.isRunning

        ToolbarItemGroup(placement: .primaryAction) {
            Button(
                String(localized: "Next Turn", bundle: .module),
                systemImage: "forward.fill"
            ) {
                controller.nextAttacker()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .help(Text("Next Turn", bundle: .module))
            .disabled(!isRunning)

            Button(
                String(localized: "Next Round", bundle: .module),
                systemImage: "arrow.uturn.backward"
            ) {
                controller.nextRound()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .help(Text("Next Round", bundle: .module))
            .disabled(!isRunning)

            // Asks first (see `BattleRoundView`'s confirmation dialog):
            // ending discards the turn order and closes this window.
            Button(
                String(localized: "End", bundle: .module),
                systemImage: "stop.fill",
                role: .destructive,
                action: screenModel.requestEnd
            )
            .help(Text("End", bundle: .module))
            .disabled(!isRunning)
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            // The system animates the inspector; no explicit animation here.
            Toggle(isOn: $screenModel.isInspectorPresented) {
                Label {
                    Text("Inspector", bundle: .module)
                } icon: {
                    Image(systemName: "sidebar.trailing")
                }
            }
            .help(Text("Inspector", bundle: .module))
        }
    }
}
#endif
