// @copyright André Trettin

import Foundation
import Testing

@testable import RolePlayGameKit

/// CODE_AUDIT §5.15: text stored in imported items must not depend on the device's locale.
@Suite("Foundry stored text")
struct FoundryStoredTextTests {
    @Test("Numbers use a fixed format without grouping", arguments: [
        (1_500.0, "1500"),
        (2.5, "2.5"),
        (-0.25, "-0.25"),
        (1_000_000.0, "1000000")
    ])
    func numbers(value: Double, expected: String) {
        #expect(FoundryStoredText.number(value) == expected)
    }

    @Test("Dates are UTC ISO-8601")
    func dates() {
        let date = Date(timeIntervalSince1970: 1_704_067_200)

        #expect(FoundryStoredText.date(date) == "2024-01-01T00:00:00Z")
    }
}
