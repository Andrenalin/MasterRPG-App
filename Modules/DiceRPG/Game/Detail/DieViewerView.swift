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
    /// Grows with Dynamic Type next to the result text. See CODE_AUDIT §8.1.
    @ScaledMetric(relativeTo: .title) private var dieSize: CGFloat = 44

    /// Gives the roll's rotation animation time to finish before resetting it back to 0 for
    /// the next roll. See CODE_AUDIT §9.14.
    private static let rotationResetDelay: Duration = .seconds(0.60)

    /// Cancelled and replaced on every rotation change so a rapid sequence of
    /// rolls can't queue up multiple resets racing to clobber a newer roll's
    /// state. See CODE_AUDIT §3.1.
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        die.diceImage(for: die.result.last ?? die.die.max)
            .resizable()
            .frame(width: dieSize, height: dieSize)
            .rotation3DEffect(.degrees(withoutResult ? 0 : die.rotation), axis: (x: 0, y: 0, z: 1))
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(.circle)
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(width: dieSize, height: dieSize)
                            .background(.ultraThinMaterial)
                            .clipShape(.circle)
                            .overlay(Circle().stroke(lineWidth: 4).foregroundStyle(.white))
                            .offset(x: 0, y: -10 + CGFloat((index + 1) * 36))
                            .opacity(index == 0 ? 0 : 1)
                            .accessibilityHidden(index == 0)
                    }
                }
            }
            .shadow(radius: 8)
            .animation(
                Animation.spring(response: 0.35, dampingFraction: 0.7).delay(0.5).reduced(if: reduceMotion),
                value: die.rotation
            )
            .animation(Animation.default.delay(0.5).reduced(if: reduceMotion), value: die.result)
            .onChange(of: die.rotation, initial: true) {
                resetTask?.cancel()
                if die.rotation != 0 {
                    resetTask = Task { @MainActor in
                        try? await Task.sleep(for: Self.rotationResetDelay)
                        guard !Task.isCancelled else { return }
                        var die = gameController.gameItem(for: diceId).die(for: die.id)
                        die.rotation = 0
                        withAnimation(Animation.default.reduced(if: reduceMotion)) {
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
        // The colour alone loses the outcome for VoiceOver and colour-blind players, so the
        // word of each result follows its number. See CODE_AUDIT_23 §8.2.
        let values = result.indexed().map { index, value in
            guard index < resultColor.count else { return String(value) }
            let outcome = resultColor[index]
                ? String(localized: "Success", bundle: .module)
                : String(localized: "Failure", bundle: .module)
            return "\(value) \(outcome)"
        }
        return Text(verbatim: values.reversed().joined(separator: ", "))
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
