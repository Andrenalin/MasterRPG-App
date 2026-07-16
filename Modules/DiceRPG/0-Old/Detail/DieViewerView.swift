// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DieViewerView: View {
    let gameController: GameController
    let diceId: UUID
    let die: DieModel
    let withoutResult: Bool
    let resultColor: [Bool]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        Text(result, format: .number)
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
                            .accessibilityHidden(index == 0)
                    }
                }
            }
            .shadow(radius: 8)
            .animation(
                reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7).delay(0.5),
                value: die.rotation
            )
            .animation(reduceMotion ? nil : .default.delay(0.5), value: die.result)
            .onChange(of: die.rotation, initial: true) {
                if die.rotation != 0 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.60))
                        var die = gameController.gameItem(for: diceId).die(for: die.id)
                        die.rotation = 0
                        withAnimation(reduceMotion ? nil : .default) {
                            gameController.gameItem(for: diceId).resetDie(die)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(die.die.text) die", bundle: .module))
            .accessibilityValue(accessibilityValue)
    }
    
    var result: [Int] {
        die.result.reversed()
    }
    
    func color(for index: Int) -> Color {
        guard index < resultColor.count else { return .primary }
        return resultColor[index] == true ? .green : .red
    }

    private var accessibilityValue: Text {
        if withoutResult || die.result.isEmpty {
            return Text("Not rolled", bundle: .module)
        }
        return Text(verbatim: die.result.map(String.init).joined(separator: ", "))
    }
}

#Preview {
    Group {
        DieViewerView(gameController: .preview, diceId: DiceModel.previewId, die: .previewDisplayTen, withoutResult: true, resultColor: [])
        DieViewerView(gameController: .preview, diceId: DiceModel.previewId, die: .previewDisplayTwenty, withoutResult: true, resultColor: [])
        DieViewerView(gameController: .preview, diceId: DiceModel.previewId, die: .previewDisplaySuccess, withoutResult: false, resultColor: [true, false])
        DieViewerView(gameController: .preview, diceId: DiceModel.previewId, die: .previewDisplayFailure, withoutResult: false, resultColor: [false, true])
    }
    .padding(32)
    .background(.blue.opacity(0.8))
}
