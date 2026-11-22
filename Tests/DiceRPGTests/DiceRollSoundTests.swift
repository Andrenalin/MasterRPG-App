// @copyright André Trettin

#if canImport(Testing)
import AVFoundation
import CoreRPG
import Foundation
import RPGResources
import Testing

@testable import DiceRPG

@MainActor
struct DiceRollSoundTests {
    private static func gameController(with dice: DiceModel) async -> GameController {
        let root = DiceRootModel.testRoot()
        await root.itemController.resetData()
        await root.gameController.reset()
        root.itemController.replace(model: dice, isInsert: true)
        let gameDice = root.gameController.gameItem(for: dice.id)
        root.gameController.setGame(item: gameDice, itemId: dice.id)
        return root.gameController
    }

    private static func dice() -> DiceModel {
        DiceModel(
            id: UUID(),
            name: "Sound",
            dice: [DieModel(id: UUID(), die: .twenty, rotation: 0, result: [], displayState: 3)]
        )
    }

    /// Every roll sound name resolves to a file in the resource bundle. `Resources` inside DiceRPG is
    /// the module's own bundle holder, which has no audio: the roll was silent when it was used.
    @Test func everyRollSoundIsInTheResourceBundle() {
        for name in (1...9).map({ "D20_\($0)" }) + (1...6).map({ "2D20_\($0)" }) {
            #expect(RPGResources.Resources.bundle.url(forResource: name, withExtension: "m4a") != nil, "\(name)")
        }
    }

    @Test func rollQueuesItsSound() async throws {
        let dice = Self.dice()
        let sut = await Self.gameController(with: dice)

        sut.roll(die: nil, for: dice.id)

        let player = sut.diceGameModel.audioPlayer
        // `replaceCurrentItem` takes effect asynchronously.
        let _ = await awaitCondition { player.currentItem != nil }
        #expect(player.volume == GameController.diceSoundVolume)
    }

    @Test func tossedDieMakesNoSoundOfItsOwn() async throws {
        let dice = Self.dice()
        let sut = await Self.gameController(with: dice)
        let die = try #require(sut.gameItem(for: dice.id).dice.first)

        _ = sut.rollDie(die.id, of: dice.id, networkActions: nil)

        try await Task.sleep(for: .milliseconds(200))
        #expect(sut.diceGameModel.audioPlayer.currentItem == nil)
    }
}
#endif
