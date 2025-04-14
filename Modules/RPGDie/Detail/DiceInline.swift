// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DiceInline: View {
    let itemId: UUID
    let resultCategory: ResultCategory
    var onlyPrimaryAction: Bool = false

    @Environment(DiceRoot.self) private var root

    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions

    @State private var showResult = false

    var body: some View {
        HStack {
            if onlyPrimaryAction {
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
                        Label { Text(roleShareTitle, bundle: .module) } icon: { Image(systemName: root.itemController.itemDataModel.networkModule.icon) }
                    }

                    Button {
                        withAnimation { root.gameController.gameModel.focusItemIds = [itemId] }
                    } label: {
                        Label { Text("Add as focus", bundle: .module) } icon: { Image(systemName: "house") }
                    }

                    if gameModus == .master {
                        Button {
                            Task {
                                if let result = try? await root.gameController.createGameData(for: itemId, resultCategory: resultCategory) {
                                    networkActions?.game(result, .show)
                                }
                            }
                        } label: {
                            Label { Text("Share", bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") }
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
//                } primaryAction: {
//                    Task {
//                        if gameModus == .master {
//                            if let result = try? await root.gameController.createGameData(for: itemId, resultCategory: resultCategory) {
//                                networkActions?.game(result, .show)
//                            }
//                        } else {
//                            await roleAndShareDiceResult()
//                        }
//                    }
                }
                #if !os(tvOS)
                .menuStyle(.borderlessButton)
                #endif
                #if os(macOS)
                .fixedSize()
                #endif
            }
            if showResult {
                Text("\(Image(systemName: root.itemController.itemDataModel.networkModule.icon))\(root.gameController.resultText(itemId: itemId))")
            }
        }
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
        .environment(DiceRoot.preview)
}
