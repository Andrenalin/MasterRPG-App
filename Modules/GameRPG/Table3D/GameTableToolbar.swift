// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import MapRPG
import PhotoRPG
import SwiftUI

@MainActor
struct GameTableToolbar: View {
    let game: GameTableModel

    var body: some View {
        HStack {
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
                .help(Text(pointerTitle))

                Button {
                    game.movePointerToMapCenter()
                } label: {
                    Label {
                        Text("Center Pointer", bundle: .module)
                    } icon: {
                        Image(systemName: "scope")
                    }
                }
                .help(Text("Center Pointer", bundle: .module))
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
            .help(Text("Reset", bundle: .module))
        }
        .labelStyle(.iconOnly)
        .padding()
        .modifier(GameTableToolbarBackground())
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
        .disabled(game.rooms.isEmpty)
        .help(Text("Room Visibility", bundle: .module))
    }
}

private struct GameTableToolbarBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(visionOS)
        content.glassBackgroundEffect()
#else
        content.background(.regularMaterial, in: .capsule)
#endif
    }
}

#Preview {
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
