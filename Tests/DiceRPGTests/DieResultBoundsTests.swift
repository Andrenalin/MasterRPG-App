// @copyright André Trettin

import Foundation
import Testing

@testable import DiceRPG

/// CODE_AUDIT_21 §6.7: a roll a peer reports, or a decoded die, can carry any `Int`.
@Suite("Die result bounds")
struct DieResultBoundsTests {
    @Test("Results are clamped to what the die can show")
    func resultsAreClamped() {
        let die = RawDie(text: "d6")
        let model = DieModel(id: UUID(), die: die, result: [Int.max, Int.max, -4, 3, 6, 7])
        #expect(model.result == [6, 6, 0, 3, 6, 6])
        // The sum that trapped: `Int.max + Int.max`.
        #expect(model.result.reduce(0, +) == 27)
    }

    @Test("A die keeps at most the bounded number of results")
    func resultCountIsBounded() {
        let model = DieModel(id: UUID(), die: RawDie(text: "d20"), result: Array(repeating: 1, count: 5_000))
        #expect(model.result.count == DieModel.maximumResultCount)
    }

    @Test("A decoded die is bounded like a constructed one")
    func decodedResultsAreBounded() throws {
        let encoded = try JSONEncoder().encode(DieModel(id: UUID(), die: RawDie(text: "d6"), result: [2]))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["result"] = [Int.max, Int.max, -1, 4]
        let tampered = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(DieModel.self, from: tampered)

        #expect(decoded.result == [6, 6, 0, 4])
    }
}
