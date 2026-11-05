// @copyright André Trettin

#if !os(tvOS)
import CharacterRPG
import CoreRPG
import SwiftUI

/// The game master's player list: the connected devices, and the Characters the game master
/// puts at the table as players. Those get a player pin on every shown map.
struct TablePlayersView: View {
    let root: GameRoot

    @State private var model: TablePlayersModel

    init(root: GameRoot) {
        self.root = root
        _model = State(initialValue: root.makeTablePlayersModel())
    }

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        // No NavigationStack toolbar: a popover does not show one on macOS (and not reliably
        // elsewhere), which left the panel without a way to add Characters.
        VStack(spacing: 0) {
            TablePlayersHeader(model: model)
            Divider()
            if model.isPicking {
                root.characterRoot.viewController.linkListView(
                    type: .selectionInline,
                    itemSelectionModel: model.selectionModel
                )
            } else {
                TablePlayersList(root: root, model: model)
            }
        }
        .themedSurface()
    }
}

/// The panel's title; while picking Characters also Cancel and Add.
private struct TablePlayersHeader: View {
    let model: TablePlayersModel

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
                } else {
                    Text("Players", bundle: .module)
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

    @State private var showAttachments = true

    var body: some View {
        @Bindable var gameModel = root.gameModel
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

            SharingOptionsSection(features: $gameModel.gameControl.features)
            AttachmentSection(logController: root.logGameController, isExpanded: $showAttachments)
            LogRowsSection(logController: root.logGameController)
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

        HStack {
            root.characterRoot.viewController.playerAvatar(
                for: isObserver ? nil : player.characterId,
                placeholderSystemImage: isObserver ? "eye" : "person"
            )

            VStack(alignment: .leading) {
                Text(verbatim: player.name)
                Group {
                    if !isSharing {
                        Text("Updates paused", bundle: .module)
                    } else if isObserver {
                        Text("Observer", bundle: .module)
                    } else if let characterName {
                        Text("Player: \(characterName)", bundle: .module)
                    } else {
                        Text("Player", bundle: .module)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if hasPin {
                    PinControllersCaption(root: root, pinId: player.id)
                }
            }

            Spacer(minLength: 0)

            if hasPin {
                PinControllersMenu(root: root, pinId: player.id)
            }

            Toggle(isOn: Binding {
                isSharing
            } set: { show in
                setSharing(show)
            }) {
                Text("Send Updates", bundle: .module)
            }
            .labelsHidden()
        }
        .accessibilityElement(children: .contain)
    }

    /// Only a player with a Character gets a pin; an observer never has one.
    private var hasPin: Bool {
        player.type == .player && player.characterId != nil
    }

    /// The same path as the old share button: `resetPlayers()` then applies the change.
    private func setSharing(_ show: Bool) {
        var controls = root.gameModel.gameControl.controls
        if let index = controls.firstIndex(where: { $0.id == player.id }) {
            guard controls[index].show != show else { return }
            controls[index].show = show
        } else {
            controls.append(SharingControlModel(id: player.id, name: player.name, show: show))
        }
        root.sharingControlActions.update?(controls)
    }
}

private struct TablePlayerRow: View {
    let root: GameRoot
    let model: TablePlayersModel
    let tablePlayer: TablePlayerModel
    let roster: [PlayerGameModel]

    var body: some View {
        let name = root.characterRoot.valueGameControllable.playerPinName(for: tablePlayer.characterId)
        let status = TablePlayerResolver.status(of: tablePlayer, roster: roster, characterExists: name != nil)

        HStack {
            root.characterRoot.viewController.playerAvatar(
                for: tablePlayer.characterId,
                placeholderSystemImage: "person"
            )

            VStack(alignment: .leading) {
                if let name {
                    Text(verbatim: name)
                } else {
                    Text("Unknown Character", bundle: .module)
                }
                TablePlayerStatusText(status: status)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if status == .active || status == .disabled {
                    PinControllersCaption(root: root, pinId: tablePlayer.id)
                }
            }

            Spacer(minLength: 0)

            if status == .active || status == .disabled {
                PinControllersMenu(root: root, pinId: tablePlayer.id)
            }

            Toggle(isOn: Binding {
                tablePlayer.isEnabled
            } set: { isEnabled in
                model.setEnabled(isEnabled, id: tablePlayer.id)
            }) {
                Text("Player Pin", bundle: .module)
            }
            .labelsHidden()
            .disabled(status == .missing)

#if os(macOS) || os(visionOS)
            Button(role: .destructive) {
                model.remove(id: tablePlayer.id)
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
        .accessibilityElement(children: .contain)
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

/// Opens `TablePlayersView`. Master only.
struct TablePlayersButton: View {
    let root: GameRoot

    @State private var isPresented = false

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Button {
            isPresented.toggle()
        } label: {
            Label {
                Text("Players", bundle: .module)
            } icon: {
                Image(systemName: "person.3")
            }
            .labelStyle(.iconOnly)
        }
        .help(Text("Players", bundle: .module))
        .accessibilityHint(Text("Shows the players and the Characters at the table", bundle: .module))
        .popover(isPresented: $isPresented) {
            ManagedPresentationView {
                TablePlayersView(root: root)
            }
            .frame(minWidth: 340, idealWidth: 400, minHeight: 480, idealHeight: 620)
        }
    }
}

#Preview(traits: .mockData) {
    TablePlayersView(root: GameRoot.previewFixture())
}
#endif
