// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import MapRPG
import PhotoRPG
import SwiftUI

@MainActor
struct GameTableToolbar: View {
    let game: GameTableModel

    var body: some View {
        HStack {
            GameTableWindowButton()

            if game.isGameMaster {
                RoomVisibilityMenu(game: game)

                Button {
                    game.togglePointerVisibility()
                } label: {
                    Label {
                        Text(pointerTitle)
                    } icon: {
                        Image(systemName: game.pointer?.isShown == true ? "hand.point.up.left.fill" : "hand.point.up.left")
                    }
                }
                .selectedRoundButton(
                    title: String(localized: pointerTitle),
                    module: .table,
                    isSelected: game.pointer?.isShown == true
                )

                Button {
                    game.movePointerToMapCenter()
                } label: {
                    Label {
                        Text("Center Pointer", bundle: .module)
                    } icon: {
                        Image(systemName: "scope")
                    }
                }
                .selectedRoundButton(
                    title: String(localized: "Center Pointer", bundle: .module),
                    module: .table,
                    isSelected: false
                )
            }

            Button {
                game.resetGame()
            } label: {
                Label {
                    Text("Reset", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
            .selectedRoundButton(
                title: String(localized: "Reset", bundle: .module),
                module: .table,
                isSelected: false
            )
        }
        .padding()
    }

    private var pointerTitle: LocalizedStringResource {
        game.pointer?.isShown == true
            ? LocalizedStringResource("Hide Pointer", bundle: .module)
            : LocalizedStringResource("Show Pointer", bundle: .module)
    }
}

@MainActor
private struct RoomVisibilityMenu: View {
    let game: GameTableModel

    var body: some View {
        Menu {
            Button {
                Task { await game.setAllRoomsShown(true) }
            } label: {
                Label {
                    Text("Show All Rooms", bundle: .module)
                } icon: {
                    Image(systemName: "eye")
                }
            }
            .disabled(game.rooms.allSatisfy { $0.isShown })

            Button {
                Task { await game.setAllRoomsShown(false) }
            } label: {
                Label {
                    Text("Hide All Rooms", bundle: .module)
                } icon: {
                    Image(systemName: "eye.slash")
                }
            }
            .disabled(game.rooms.allSatisfy { !$0.isShown })

            Divider()

            ForEach(game.rooms) { room in
                Button {
                    Task { await game.toggleRoomVisibility(room.id) }
                } label: {
                    Label {
                        if room.name.isEmpty {
                            Text("Unnamed Room", bundle: .module)
                        } else {
                            Text(room.name)
                        }
                    } icon: {
                        Image(systemName: room.isShown ? "eye" : "eye.slash")
                    }
                }
            }
        } label: {
            Label {
                Text("Rooms", bundle: .module)
            } icon: {
                Image(systemName: "door.left.hand.open")
            }
        }
        .selectedRoundButton(
            title: String(localized: "Room Visibility", bundle: .module),
            module: .table,
            isSelected: false
        )
        .disabled(game.rooms.isEmpty)
    }
}

#Preview(traits: .mockData) {
    @Previewable @State var game: GameTableModel?

    Group {
        if let game {
            GameTableToolbar(game: game)
        } else {
            ProgressView()
        }
    }
    .task {
        game = GameTableModel(mapRoot: .preview, photoRoot: .preview)
    }
}

#endif
