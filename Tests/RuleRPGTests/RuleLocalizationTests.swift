// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import RuleRPG

/// CODE_AUDIT_28 §8.2: the entry-kind titles were looked up in the main bundle.
@Suite("Rule localization")
struct RuleLocalizationTests {
    @Test("Entry kind titles come from the module's German catalog")
    func entryKindTitlesAreLocalized() {
        func german(_ kind: RuleEntryKind) -> String {
            var resource = kind.localizedTitle
            resource.locale = Locale(identifier: "de")
            return String(localized: resource)
        }

        #expect(german(.text) == "Abschnitte")
        #expect(german(.group) == "Gruppen")
        #expect(german(.embeddedRule) == "Eingebettete Regeln")
    }
}
#endif
