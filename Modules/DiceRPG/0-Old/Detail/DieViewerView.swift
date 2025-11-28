// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DieViewerView: View {
    let gameController: GameController
    let diceId: UUID
    let die: DieModel
    let withoutResult: Bool
    let resultColor: [Bool]

    var body: some View {
        die.diceImage(for: die.result.last ?? die.die.max)
            .resizable()
            .frame(width: 44, height: 44)
            .rotation3DEffect(.degrees(withoutResult ? 0 : die.rotation), axis: (x: 0, y: 0, z: 1))
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .overlay(Circle().stroke(lineWidth: 4).foregroundStyle(.white))
            .overlay(alignment: .top) {
                if !withoutResult {
                    ForEach(result.indexed(), id: \.0) { index, result in
                        Text("\(result)")
#if os(tvOS)
                            .font(.body)
#else
                            .font(.title)
#endif
                            .foregroundStyle(color(for: index))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(lineWidth: 4).foregroundStyle(.white))
                            .offset(x: 0, y: -10 + CGFloat((index + 1) * 36))
                            .opacity(index == 0 ? 0 : 1)
                    }
                }
            }
            .shadow(radius: 8)
            .animation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.5), value: die.rotation)
            .animation(.default.delay(0.5), value: die.result)
            .onChange(of: die.rotation, initial: true) {
                if die.rotation != 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
                        var die = gameController.gameItem(for: diceId).die(for: die.id)
                        die.rotation = 0
                        withAnimation {
                            gameController.gameItem(for: diceId).resetDie(die)
                        }
                    }
                }
            }
    }
    
    var result: [Int] {
        die.result.reversed()
    }
    
    func color(for index: Int) -> Color {
        guard index < resultColor.count else { return .primary }
        return resultColor[index] == true ? .green : .red
    }
}

#Preview {
    Group {
        DieViewerView(gameController: .preview, diceId: DiceModel.previewId, die: DieModel.die10, withoutResult: true, resultColor: [])
        DieViewerView(gameController: .preview, diceId: DiceModel.previewId, die: DieModel.die20.role(reroleOptions: [DiceModel.RerollOption(number: 1, value: 20, maxDiceValue: false)]), withoutResult: true, resultColor: [])
        DieViewerView(gameController: .preview, diceId: DiceModel.previewId, die: DieModel.die20.role(reroleOptions: [DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true)]), withoutResult: false, resultColor: [true, false])
        DieViewerView(gameController: .preview, diceId: DiceModel.previewId, die: DieModel.die20.role(reroleOptions: [DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true)]), withoutResult: false, resultColor: [true, false])
    }
    .padding(32)
    .background(.blue.opacity(0.8))
}
