// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import TableRPG

/// CODE_AUDIT_TestGaps §8.5: the table generation view keeps the first generation model of its
/// session however often the parent rebuilds the view.
@MainActor
@Suite("Lazy generation model")
struct LazyGenerationModelTests {
    private func generation() -> TableGenerationModel {
        TableGenerationModel(root: TableGenerationOccurrence(
            tableId: UUID(),
            tableName: "Loot",
            tableType: .list,
            diceId: nil,
            entries: [],
            depth: 0,
            tablePath: []
        ))
    }

    @Test("The model is made on the first request and kept")
    func madeOnce() {
        let box = LazyGenerationModel()
        var made = 0

        let first = box.model { made += 1; return generation() }
        let second = box.model { made += 1; return generation() }

        #expect(made == 1)
        #expect(first === second)
    }

    @Test("A second box makes its own model")
    func boxesAreIndependent() {
        let first = LazyGenerationModel().model { generation() }
        let second = LazyGenerationModel().model { generation() }

        #expect(first !== second)
    }
}
#endif
