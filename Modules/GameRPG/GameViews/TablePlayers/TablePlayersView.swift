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
struct TablePlayersHeader: View {
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

#endif
