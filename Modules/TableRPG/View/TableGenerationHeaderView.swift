// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGenerationHeaderView: View {
    let model: TableGenerationModel
    let controller: TableGenerationController

    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingControlActions) private var sharingControlActions
    @Environment(AppGameStateModel.self) private var gameState

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.root.tableName)
                    .font(.title)
                    .bold()
                Text("Choose the results for each generated table.", bundle: .module)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if gameState.isGameRunning,
               gameState.gameModus == .master,
               networkActions != nil,
               model.summary != nil {
                Menu {
                    ForEach(visiblePlayers) { player in
                        Button {
                            shareSummary(to: player.id)
                        } label: {
                            Label {
                                Text("Share with \(player.name)", bundle: .module)
                            } icon: {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                            }
                        }
                    }
                } label: {
                    Label {
                        Text("Share", bundle: .module)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
#if !os(visionOS)
                .buttonStyle(.glass)
#endif
                .disabled(visiblePlayers.isEmpty)
            }

            GlassButton(isProminent: true) {
                withAnimation {
                    controller.autoRoll(model: model)
                }
            } label: {
                Label {
                    Text("Auto Roll", bundle: .module)
                } icon: {
                    Image(systemName: "dice.fill")
                }
            }
            .disabled(model.root.entries.isEmpty)
        }
        .padding()
    }

    private var visiblePlayers: [SharingControlModel] {
        (sharingControlActions.control?() ?? [])
            .filter(\.show)
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func shareSummary(to playerId: UUID) {
        guard let summary = model.summary,
              let data = summary.encodeData()
        else {
            return
        }
        networkActions?.game(
            NetworkCodableDataType(
                id: summary.id,
                type: .generator,
                version: 1,
                data: data
            ),
            .generatedValue,
            playerId
        )
    }
}

#Preview("Dice table", traits: .mockData) {
    TableGenerationHeaderView(model: .preview, controller: .preview)
}

#Preview("Empty table", traits: .mockData) {
    TableGenerationHeaderView(model: .previewEmpty, controller: .preview)
}
