// @copyright André Trettin

#if !os(tvOS)
import CharacterRPG
import CoreRPG
import SwiftUI

/// The game master's player list: the connected devices, their companions, and the Characters
/// the game master puts at the table as players. For a player it lists only the companions it
/// brings along. Each of those gets a player pin on every shown map.
///
/// The role and the list model are read from `root` once, when the view is created. A role that
/// changes later needs a new view: the call site keys it with `.id(isMaster)`.
/// See CODE_AUDIT_24 §8.1.
struct TablePlayersView: View {
    let root: GameRoot

    @State private var model: TablePlayersModel
    private let isMaster: Bool

    init(root: GameRoot) {
        self.root = root
        let isMaster = root.gameModel.gameConfig.isMaster
        self.isMaster = isMaster
        _model = State(initialValue: isMaster ? root.makeTablePlayersModel() : root.makeCompanionsModel())
    }

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        // No NavigationStack toolbar: a popover does not show one on macOS (and not reliably
        // elsewhere), which left the panel without a way to add Characters.
        VStack(spacing: 0) {
            TablePlayersHeader(model: model, isMaster: isMaster)
            Divider()
            if model.isPicking {
                root.characterRoot.viewController.linkListView(
                    type: .selectionInline,
                    itemSelectionModel: model.selectionModel
                )
            } else if isMaster {
                TablePlayersList(root: root, model: model)
            } else {
                CompanionsList(root: root, model: model)
            }
        }
        .themedSurface()
    }
}

/// The panel's title; while picking Characters also Cancel and Add.
private struct TablePlayersHeader: View {
    let model: TablePlayersModel
    let isMaster: Bool

    var body: some View {
        HStack {
            if model.isPicking {
                Button(action: model.cancelPicking) {
                    Text("Cancel", bundle: .module)
                }
            }

            Spacer(minLength: 0)

            Group {
                if model.isPicking {
                    Text("Add Characters", bundle: .module)
                } else if isMaster {
                    Text("Players", bundle: .module)
                } else {
                    Text("Companions", bundle: .module)
                }
            }
            .font(.headline)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if model.isPicking {
                Button(action: model.addPicked) {
                    Text("Add", bundle: .module)
                        .bold()
                }
                .disabled(model.selectionModel.selection.isEmpty)
            }
        }
        .buttonStyle(.borderless)
        .padding()
    }
}

/// The connected players with their "send updates" switch, the Characters at the table, and
/// what the Logs window shows: the sharing options, the SharePlay attachments and the messages.
private struct TablePlayersList: View {
    let root: GameRoot
    let model: TablePlayersModel

    var body: some View {
        let gameModel = root.gameModel
        let connected = gameModel.gameRoster.players
        let tablePlayers = gameModel.tablePlayers

        List {
            Section {
                if connected.isEmpty {
                    Text("No players connected", bundle: .module)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(connected) { player in
                        ConnectedPlayerRow(root: root, player: player)
                    }
                }
            } header: {
                Text("Connected", bundle: .module)
            }

            let companions = connected.filter { $0.type == .player }.flatMap { player in
                player.companions.map { CompanionEntry(owner: player, companion: $0) }
            }
            if !companions.isEmpty {
                Section {
                    ForEach(companions) { entry in
                        MasterCompanionRow(root: root, owner: entry.owner, companion: entry.companion, roster: connected)
                    }
                } header: {
                    Text("Companions", bundle: .module)
                } footer: {
                    Text("Characters the players bring along. Each is moved by its player unless you choose otherwise.", bundle: .module)
                }
            }

            Section {
                if tablePlayers.isEmpty {
                    Text("No Characters at the table", bundle: .module)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tablePlayers) { tablePlayer in
                        TablePlayerRow(root: root, model: model, tablePlayer: tablePlayer, roster: connected)
                    }
                    .onDelete(perform: model.remove(atOffsets:))
                }

                Button(action: model.startPicking) {
                    Label {
                        Text("Add Characters", bundle: .module)
                    } icon: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            } header: {
                Text("Characters at the Table", bundle: .module)
            } footer: {
                Text("Each enabled Character gets a player pin on every shown map, like a joined player. A player who joins with the same Character takes over its pin.", bundle: .module)
            }

            LogSections(logController: root.logGameController)
        }
        .listStyle(.inset)
        .themedListSurface()
    }
}

/// A connected device, laid out like a Character at the table. It cannot be removed; its
/// switch pauses the updates the game master sends it.
private struct ConnectedPlayerRow: View {
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
private struct TablePlayerRow: View {
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

private struct CompanionEntry: Identifiable {
    let owner: PlayerGameModel
    let companion: TablePlayerModel

    var id: UUID { companion.id }
}

/// A player's own list: the companions it brings along. Each enabled one gets a player pin
/// that this player moves, unless the game master hands it to someone else.
private struct CompanionsList: View {
    let root: GameRoot
    let model: TablePlayersModel

    var body: some View {
        let player = root.gameModel.gamePlayer
        let roster = root.gameModel.gameRoster.players

        List {
            Section {
                if player.companions.isEmpty {
                    Text("No companions", bundle: .module)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(player.companions) { companion in
                        CompanionRow(root: root, model: model, companion: companion, roster: roster)
                    }
                    .onDelete(perform: model.remove(atOffsets:))
                }

                if player.companions.count < PlayerGameModel.maximumCompanions {
                    Button(action: model.startPicking) {
                        Label {
                            Text("Add Companions", bundle: .module)
                        } icon: {
                            Image(systemName: "person.badge.plus")
                        }
                    }
                }
            } header: {
                Text("Companions at the Table", bundle: .module)
            } footer: {
                Text("Each enabled companion gets a player pin on every shown map, which you move. The game master can let others move it.", bundle: .module)
            }
        }
        .listStyle(.inset)
        .themedListSurface()
    }
}

/// A companion in the player's own list: like a Character at the table, without the
/// game master's controller menu.
private struct CompanionRow: View {
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
private struct MasterCompanionRow: View {
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
private struct PlayerRowLayout<Name: View, Status: View, Trailing: View>: View {
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
private struct TablePlayerPinToggle: View {
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
private struct CharacterNameText: View {
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
private struct TablePlayerRemoveButton: View {
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

/// Picks the connected devices (players and observers) that may move the player pin `pinId`
/// besides its own player. The pin's own player is not listed: it always moves its pin.
private struct PinControllersMenu: View {
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
private struct PinControllersCaption: View {
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

private struct TablePlayerStatusText: View {
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

/// Opens `TablePlayersView`: the game master's players, or a player's companions.
struct TablePlayersButton: View {
    let root: GameRoot

    @State private var isPresented = false

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        let isMaster = root.gameModel.gameConfig.isMaster
        Button {
            isPresented.toggle()
        } label: {
            Label {
                if isMaster {
                    Text("Players", bundle: .module)
                } else {
                    Text("Companions", bundle: .module)
                }
            } icon: {
                Image(systemName: isMaster ? "person.3" : "person.2")
            }
            .labelStyle(.iconOnly)
        }
        .help(isMaster ? Text("Players", bundle: .module) : Text("Companions", bundle: .module))
        .accessibilityHint(isMaster
            ? Text("Shows the players and the Characters at the table", bundle: .module)
            : Text("Shows the companions you bring to the table", bundle: .module))
        .popover(isPresented: $isPresented) {
            ManagedPresentationView {
                TablePlayersView(root: root)
                    .id(isMaster)
            }
            .frame(minWidth: 340, idealWidth: 400, minHeight: 480, idealHeight: 620)
        }
    }
}

#Preview(traits: .mockData) {
    TablePlayersView(root: GameRoot.previewFixture())
}
#endif
