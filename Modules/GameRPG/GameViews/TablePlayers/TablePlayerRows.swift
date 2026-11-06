// @copyright André Trettin

#if !os(tvOS)
import CharacterRPG
import CoreRPG
import SwiftUI

/// A connected device, laid out like a Character at the table. It cannot be removed; its
/// switch pauses the updates the game master sends it.
struct ConnectedPlayerRow: View {
    let root: GameRoot
    let player: PlayerGameModel

    var body: some View {
        let isObserver = player.type == .observer
        let characterName = player.characterId.flatMap {
            root.characterRoot.valueGameControllable.playerPinName(for: $0)
        }
        let isSharing = root.gameModel.gameControl.controls.first { $0.id == player.id }?.show ?? true

        PlayerRowLayout(
            root: root,
            avatarCharacterId: isObserver ? nil : player.characterId,
            placeholderSystemImage: isObserver ? "eye" : "person",
            pinId: hasPin ? player.id : nil
        ) {
            Text(verbatim: player.name)
        } status: {
            if !isSharing {
                Text("Updates paused", bundle: .module)
            } else if isObserver {
                Text("Observer", bundle: .module)
            } else if let characterName {
                Text("Player: \(characterName)", bundle: .module)
            } else {
                Text("Player", bundle: .module)
            }
        } trailing: {
            Toggle(isOn: Binding {
                isSharing
            } set: { show in
                root.setSharing(show, for: player)
            }) {
                Text("Send Updates", bundle: .module)
            }
            .labelsHidden()
        }
    }

    /// Only a player with a Character gets a pin; an observer never has one.
    private var hasPin: Bool {
        player.type == .player && player.characterId != nil
    }
}

/// A Character at the table, in the game master's list: its pin switch and its removal.
struct TablePlayerRow: View {
    let root: GameRoot
    let model: TablePlayersModel
    let tablePlayer: TablePlayerModel
    let roster: [PlayerGameModel]

    var body: some View {
        let name = root.characterRoot.valueGameControllable.playerPinName(for: tablePlayer.characterId)
        let status = TablePlayerResolver.status(of: tablePlayer, roster: roster, characterExists: name != nil)

        PlayerRowLayout(
            root: root,
            avatarCharacterId: tablePlayer.characterId,
            placeholderSystemImage: "person",
            pinId: status == .active || status == .disabled ? tablePlayer.id : nil
        ) {
            CharacterNameText(name: name)
        } status: {
            TablePlayerStatusText(status: status)
        } trailing: {
            TablePlayerPinToggle(model: model, player: tablePlayer, status: status)
            TablePlayerRemoveButton(model: model, id: tablePlayer.id)
        }
    }
}

/// A companion in the player's own list: like a Character at the table, without the
/// game master's controller menu.
struct CompanionRow: View {
    let root: GameRoot
    let model: TablePlayersModel
    let companion: TablePlayerModel
    let roster: [PlayerGameModel]

    var body: some View {
        let name = root.characterRoot.valueGameControllable.playerPinName(for: companion.characterId)
        let status = TablePlayerResolver.status(of: companion, roster: roster, characterExists: name != nil)

        PlayerRowLayout(
            root: root,
            avatarCharacterId: companion.characterId,
            placeholderSystemImage: "person",
            pinId: nil
        ) {
            CharacterNameText(name: name)
        } status: {
            TablePlayerStatusText(status: status)
        } trailing: {
            TablePlayerPinToggle(model: model, player: companion, status: status)
            TablePlayerRemoveButton(model: model, id: companion.id)
        }
    }
}

/// A companion of a connected player in the game master's list. The player adds, switches and
/// removes it; the game master decides who moves its pin.
struct MasterCompanionRow: View {
    let root: GameRoot
    let owner: PlayerGameModel
    let companion: TablePlayerModel
    let roster: [PlayerGameModel]

    var body: some View {
        let name = root.characterRoot.valueGameControllable.playerPinName(for: companion.characterId)
        let status = TablePlayerResolver.status(of: companion, roster: roster, characterExists: name != nil)

        PlayerRowLayout(
            root: root,
            avatarCharacterId: companion.characterId,
            placeholderSystemImage: "person",
            pinId: status == .active ? companion.id : nil
        ) {
            CharacterNameText(name: name)
        } status: {
            Text("Companion of \(owner.name)", bundle: .module)
            if status == .missing {
                // The player's package has not arrived yet.
                Text("Waiting for the Character", bundle: .module)
            } else if status != .active {
                TablePlayerStatusText(status: status)
            }
        } trailing: {
            EmptyView()
        }
    }
}

/// The row every list at the table shares: avatar, name, status lines, and, when the player
/// has a pin on the map, who controls it. The kinds differ in their name, their status text and
/// what sits at the trailing edge.
struct PlayerRowLayout<Name: View, Status: View, Trailing: View>: View {
    let root: GameRoot
    let avatarCharacterId: UUID?
    let placeholderSystemImage: String
    /// The pin's id when the player has one: shows its controllers.
    let pinId: UUID?
    @ViewBuilder let name: Name
    @ViewBuilder let status: Status
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            root.characterRoot.viewController.playerAvatar(
                for: avatarCharacterId,
                placeholderSystemImage: placeholderSystemImage
            )

            VStack(alignment: .leading) {
                name
                Group {
                    status
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let pinId {
                    PinControllersCaption(root: root, pinId: pinId)
                }
            }

            Spacer(minLength: 0)

            if let pinId {
                PinControllersMenu(root: root, pinId: pinId)
            }

            trailing
        }
        .accessibilityElement(children: .contain)
    }
}

/// The "Player Pin" switch of a Character at the table or a companion.
struct TablePlayerPinToggle: View {
    let model: TablePlayersModel
    let player: TablePlayerModel
    let status: TablePlayerStatus

    var body: some View {
        Toggle(isOn: Binding {
            player.isEnabled
        } set: { isEnabled in
            model.setEnabled(isEnabled, id: player.id)
        }) {
            Text("Player Pin", bundle: .module)
        }
        .labelsHidden()
        .disabled(status == .missing)
    }
}

/// A Character's name, or "Unknown Character" when it does not exist on this device.
struct CharacterNameText: View {
    let name: String?

    var body: some View {
        if let name {
            Text(verbatim: name)
        } else {
            Text("Unknown Character", bundle: .module)
        }
    }
}

/// Swipe-to-delete has no pointer equivalent: macOS and visionOS get a trash button.
struct TablePlayerRemoveButton: View {
    let model: TablePlayersModel
    let id: UUID

    var body: some View {
#if os(macOS) || os(visionOS)
        Button(role: .destructive) {
            model.remove(id: id)
        } label: {
            Label {
                Text("Remove", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
#endif
    }
}

struct TablePlayerStatusText: View {
    let status: TablePlayerStatus

    var body: some View {
        switch status {
        case .active:
            Text("Pin on the map", bundle: .module)
        case .disabled:
            Text("Disabled", bundle: .module)
        case .claimed(let playerName):
            Text("Played by \(playerName)", bundle: .module)
        case .missing:
            Text("Character missing", bundle: .module)
        }
    }
}

#endif
