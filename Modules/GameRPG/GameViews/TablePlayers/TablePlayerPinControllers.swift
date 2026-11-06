// @copyright André Trettin

#if !os(tvOS)
import CharacterRPG
import CoreRPG
import SwiftUI

/// Picks the connected devices (players and observers) that may move the player pin `pinId`
/// besides its own player. The pin's own player is not listed: it always moves its pin.
struct PinControllersMenu: View {
    let root: GameRoot
    let pinId: UUID

    var body: some View {
        let devices = root.gameModel.gameRoster.players.filter { $0.id != pinId }
        let controllers = root.gameModel.pinControllers[pinId] ?? []

        Menu {
            Section {
                ForEach(devices) { device in
                    Toggle(isOn: Binding {
                        controllers.contains(device.id)
                    } set: { isEnabled in
                        root.setPinController(device.id, for: pinId, isEnabled: isEnabled)
                    }) {
                        Label {
                            Text(verbatim: device.name)
                        } icon: {
                            Image(systemName: device.type == .observer ? "eye" : "person")
                        }
                    }
                }
            } header: {
                Text("Who else may move this pin", bundle: .module)
            }
        } label: {
            Label {
                Text("Moved By", bundle: .module)
            } icon: {
                Image(systemName: controllers.isEmpty ? "hand.point.up.left" : "hand.point.up.left.fill")
            }
            .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(devices.isEmpty)
        .help(Text("Who else may move this pin", bundle: .module))
    }
}

/// "Also moved by …" under a pin's row, for the connected devices the game master chose.
struct PinControllersCaption: View {
    let root: GameRoot
    let pinId: UUID

    var body: some View {
        let controllers = root.gameModel.pinControllers[pinId] ?? []
        let names = root.gameModel.gameRoster.players
            .filter { controllers.contains($0.id) }
            .map(\.name)
        if !names.isEmpty {
            Text("Also moved by \(names.formatted(.list(type: .and)))", bundle: .module)
                .font(.caption)
                .foregroundStyle(.tint)
        }
    }
}

#endif
