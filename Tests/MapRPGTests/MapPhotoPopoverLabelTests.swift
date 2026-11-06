// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import MapRPG

/// CODE_AUDIT_24 §8.3 and §8.4: the popover's VoiceOver text.
struct MapPhotoPopoverLabelTests {
    @Test("A weather without a name is announced as \"Weather\", never as an empty label")
    func weatherWithoutNameHasALabel() {
        #expect(MapPhotoPopoverContent.weatherAccessibilityName(title: "Thunderstorm") == "Thunderstorm")
        #expect(!MapPhotoPopoverContent.weatherAccessibilityName(title: nil).isEmpty)
        #expect(!MapPhotoPopoverContent.weatherAccessibilityName(title: "").isEmpty)
        #expect(MapPhotoPopoverContent.weatherAccessibilityName(title: nil)
            == MapPhotoPopoverContent.weatherAccessibilityName(title: ""))
    }

    @Test("The popover's spoken words are translated to German and Thai", arguments: ["Photo", "Weather"])
    func popoverWordsAreTranslated(key: String) throws {
        // The compiled catalog of each language, read directly: `locale:` would not pick it.
        func word(in language: String) throws -> String {
            let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"), "\(language) is compiled in")
            let bundle = try #require(Bundle(path: path))
            return bundle.localizedString(forKey: key, value: "<missing>", table: nil)
        }
        for language in ["de", "th"] {
            let translated = try word(in: language)
            #expect(translated != "<missing>" && translated != key, "\(key) has a \(language) translation")
        }
    }
}
#endif
