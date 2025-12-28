// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceInline: View {
    let itemId: UUID
    let resultCategory: ResultCategory

    @Environment(DiceRootModel.self) private var root

    @Environment(\.showGame) private var showGame
    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingControlActions) private var playerSharingActions
    
    @State private var showResult = false

    var body: some View {
        HStack {
            if !showGame || gameModus == .player {
                Button {
                    withAnimation {
                        root.gameController.gameModel.focusItemIds <=> [itemId]
                    }
                    Task {
                        await roleAndShareDiceResult()
                    }
                } label: {
                    HStack {
                        Text(root.gameController.gameItem(for: itemId).inlineText)
                    }
                    .padding(4)
                    .foregroundStyle(.white)
                    .background {
                        RoundedRectangle(cornerRadius: 8).fill(Color.accentColor)
                    }
                }
                .borderLessTVBottonStyle()
            } else {
                MenuTV {
                    Button {
                        Task {
                            await roleAndShareDiceResult()
                        }
                    } label: {
                        Label { Text(roleShareTitle, bundle: .module) } icon: { Image(systemName: root.itemController.config.module.icon) }
                    }

                    Button {
                        withAnimation { root.gameController.gameModel.focusItemIds = [itemId] }
                    } label: {
                        Label { Text("Add as focus", bundle: .module) } icon: { Image(systemName: "house") }
                    }

                    if gameModus == .master {
                        ForEach(players) { player in
                            Button {
                                Task {
                                    if let result = try? await root.gameController.createGameData(for: itemId, resultCategory: resultCategory) {
                                        networkActions?.game(result, .show, player.id)
                                    }
                                }
                            } label: {
                                Label { Text("Share to \(player.name)", bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") }
                            }
                        }
                        
                        Button {
                            Task {
                                if let result = try? await root.gameController.createGameData(for: itemId, resultCategory: resultCategory) {
                                    networkActions?.game(result, .show, nil)
                                }
                            }
                        } label: {
                            Label { Text("Share to all", bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") }
                        }
                    }

                    Button(role: .destructive) {
                        withAnimation {
                            root.gameController.reset(for: itemId)
                            showResult = false
                        }
                    } label: {
                        Label { Text("Reset", bundle: .module) } icon: { Image(systemName: "trash.circle") }
                    }
                } label: {
                    HStack {
                        Text(root.gameController.gameItem(for: itemId).inlineText)
                    }
                    .padding(4)
                    .foregroundStyle(.white)
                    .background {
                        RoundedRectangle(cornerRadius: 8).fill(Color.accentColor)
                    }
                }
                #if !os(tvOS)
                .menuStyle(.borderlessButton)
                #endif
                #if os(macOS)
                .fixedSize()
                #endif
            }
            if showResult {
                Text("\(Image(systemName: root.itemController.config.module.icon))\(root.gameController.resultText(itemId: itemId))")
            }
        }
    }
    
    private var players: [SharingControlModel] {
        playerSharingActions.control?() ?? []
    }

    private var roleShareTitle: LocalizedStringKey {
        networkActions != nil ? "Roll" : "Roll & Share"
    }

    private func roleAndShareDiceResult() async {
        root.gameController.rollDice(itemId: itemId, networkActions: networkActions, resultCategopry: resultCategory)
        showResult <=> true
    }
}

#Preview {
    DiceInline(itemId: DiceModel.previewId, resultCategory: ResultCategory(id: UUID(), module: .dice))
        .environment(DiceRootModel.preview)
}
