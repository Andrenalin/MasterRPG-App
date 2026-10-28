// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_Since_3.0.1 §4.1: already-localized dialog text is shown as is. The dialog literal
/// `"\(message)"` looked up the key `%@`, which only showed the text while no catalog had that key.
@Suite("Verbatim intent text")
struct IntentDialogVerbatimTests {
    private let coreBundle = Bundle(for: ItemDataModel.self)

    private func resolved(_ text: String, locale: String) -> String {
        var resource = LocalizedStringResource.verbatim(text)
        resource.locale = Locale(identifier: locale)
        return String(localized: resource)
    }

    @Test("Text comes back unchanged in every language", arguments: ["en", "de", "th"])
    func unchanged(locale: String) {
        #expect(resolved("Deleted 3 adventures.", locale: locale) == "Deleted 3 adventures.")
    }

    @Test("A word the module catalog translates is not translated again")
    func catalogKeyIsNotLookedUp() {
        // CoreRPG's catalog has "Edit" → "Bearbeiten"; the verbatim text must not reach it.
        var catalogued = LocalizedStringResource("Edit", bundle: coreBundle)
        catalogued.locale = Locale(identifier: "de")
        #expect(String(localized: catalogued) == "Bearbeiten")
        #expect(resolved("Edit", locale: "de") == "Edit")
    }

    @Test("Format characters in the text stay as they are", arguments: ["50 % chance", "%@ and %d", "100%"])
    func formatCharacters(text: String) {
        #expect(resolved(text, locale: "de") == text)
    }

    @Test("An inflected attributed string keeps its inflected text")
    func attributedText() {
        let message = AttributedString(localized: "^[\(2) item](inflect: true)", locale: Locale(identifier: "en"))
        let text = String(message.characters)
        #expect(text == "2 items")
        #expect(resolved(text, locale: "en") == "2 items")
    }

    @Test("Nothing is extracted into a catalog: the table exists in no bundle")
    func tableExistsNowhere() {
        let table = LocalizedStringResource.verbatimTable
        #expect(coreBundle.path(forResource: table, ofType: "strings") == nil)
        #expect(coreBundle.path(forResource: table, ofType: "xcstrings") == nil)
        #expect(Bundle.main.path(forResource: table, ofType: "strings") == nil)
    }
}
