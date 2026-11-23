// @copyright André Trettin

#if os(visionOS)
import Testing

@testable import GameRPG

/// CODE_AUDIT_28 §9.4: the pool dice are looked up through one table, so a kind missing from it
/// would be a die that can be placed but not tossed.
@Suite("Pool die lookup")
struct PoolDieLookupTests {
    @Test("Every die kind has exactly one die type in the lookup table")
    func everyKindHasOneType() {
        for kind in TableDieKind.allCases {
            let matching = PoolDieLookup.types.filter { $0.kind == kind }
            #expect(matching.count == 1, "kind \(kind)")
            #expect(PoolDieLookup.type(of: kind).kind == kind)
        }
        #expect(PoolDieLookup.types.count == TableDieKind.allCases.count)
    }
}
#endif
