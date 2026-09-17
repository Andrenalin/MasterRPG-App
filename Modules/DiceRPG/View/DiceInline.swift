// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceInline: View {
    let itemId: UUID
    let resultCategory: ResultCategory
    let player: Bool

    @Environment(DiceRootModel.self) private var root

    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingControlActions) private var playerSharingActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var showResult = false

    var body: some View {
        HStack {
            if !appGameStateModel.isGameRunning || player {
                Button {
                    withAnimation(Animation.default.reduced(if: reduceMotion)) {
                        root.gameController.gameModel.focusItemIds <=> [itemId]
                    }
                    rollAndShareDiceResult()
                } label: {
                    DiceInlineLabel(text: root.gameController.gameItem(for: itemId).inlineText)
                }
                .frame(minHeight: 44)
                .borderLessTVBottonStyle()
            } else {
                MenuTV {
                    Button {
                        rollAndShareDiceResult()
                    } label: {
                        Label { Text(rollShareTitle, bundle: .module) } icon: { Image(systemName: root.itemController.config.module.icon) }
                    }

                    Button {
                        withAnimation(Animation.default.reduced(if: reduceMotion)) {
                            root.gameController.gameModel.focusItemIds = [itemId]
                        }
                    } label: {
                        Label { Text("Add as focus", bundle: .module) } icon: { Image(systemName: "house") }
                    }

                    if !player {
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
                        withAnimation(Animation.default.reduced(if: reduceMotion)) {
                            root.gameController.reset(for: itemId)
                            showResult = false
                        }
                    } label: {
                        Label { Text("Reset", bundle: .module) } icon: { Image(systemName: "trash.circle") }
                    }
                } label: {
                    DiceInlineLabel(text: root.gameController.gameItem(for: itemId).inlineText)
                }
                .frame(minHeight: 44)
                #if !os(tvOS)
                .menuStyle(.borderlessButton)
                #endif
                #if os(macOS)
                .fixedSize()
                #endif
            }
            if showResult {
                Label {
                    Text(verbatim: root.gameController.resultText(itemId: itemId))
                } icon: {
                    Image(systemName: root.itemController.config.module.icon)
                }
                    .animation(Animation.bouncy.reduced(if: reduceMotion), value: showResult)
            }
        }
    }
    
    private var players: [SharingControlModel] {
        playerSharingActions.control?() ?? []
    }

    private var rollShareTitle: LocalizedStringKey {
        networkActions != nil ? "Roll" : "Roll & Share"
    }

    private func rollAndShareDiceResult() {
        withAnimation(Animation.default.reduced(if: reduceMotion)) {
            root.gameController.rollDice(itemId: itemId, networkActions: networkActions, resultCategory: resultCategory)
            showResult <=> true
        }
    }
}

/// Shared label style for `DiceInline`'s plain-button and menu-button
/// branches — was duplicated verbatim between the two; see CODE_AUDIT_13 §8.11.
private struct DiceInlineLabel: View {
    let text: String

    var body: some View {
        HStack {
            Text(verbatim: text)
        }
        .padding(4)
        .foregroundStyle(.white)
        .background {
            Color.accentColor.clipShape(.rect(cornerRadius: 8))
        }
    }
}

#Preview {
    DiceInline(itemId: DiceModel.previewId, resultCategory: ResultCategory(id: UUID(), module: .dice), player: true)
        .environment(DiceRootModel.preview)
}
