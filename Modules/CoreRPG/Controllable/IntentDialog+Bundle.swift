// @copyright André Trettin

import AppIntents
import Foundation

/// Spoken replies, follow-up questions and re-prompts of the intents in a module framework.
///
/// A dialog written as a string literal is a `LocalizedStringResource` of the **app** bundle
/// (`bundle: .main` is the default), while the translations of a module's intents live in the
/// module's own string catalog — so Siri answered German and Thai users in English. Each call
/// passes `bundle: .module`; Xcode extracts the literal into that module's catalog because the
/// parameter is a `String.LocalizationValue`. Static titles and descriptions are not affected:
/// the App Intents metadata stores them as keys of the framework that ships them.
/// See CODE_AUDIT_AppIntents3 §5.1.
public extension IntentDialog {
    static func localized(_ value: String.LocalizationValue, bundle: Bundle) -> IntentDialog {
        IntentDialog(LocalizedStringResource(value, bundle: bundle))
    }

    /// `full` is what Siri reads on a device without a screen (AirPods, HomePod, CarPlay), so it
    /// must stand on its own as spoken language; `supporting` is shown next to the result on a
    /// screen. See CODE_AUDIT_AppIntents3 §4.12.
    static func localized(full: String.LocalizationValue, supporting: String.LocalizationValue, bundle: Bundle) -> IntentDialog {
        IntentDialog(
            full: LocalizedStringResource(full, bundle: bundle),
            supporting: LocalizedStringResource(supporting, bundle: bundle)
        )
    }

    /// Text that is already localized (a module's inflected count, a message of the generator or
    /// the model framework), shown as is. See `LocalizedStringResource.verbatim(_:)`.
    static func verbatim(_ text: String) -> IntentDialog {
        IntentDialog(.verbatim(text))
    }

    /// An inflected `AttributedString(localized:)` as is; the inflection already happened there.
    static func verbatim(_ text: AttributedString) -> IntentDialog {
        verbatim(String(text.characters))
    }
}

public extension LocalizedStringResource {
    /// A runtime string of an intent (a dialog part, an error) localized from `bundle`.
    /// See `IntentDialog.localized(_:bundle:)`.
    static func intent(_ value: String.LocalizationValue, bundle: Bundle) -> LocalizedStringResource {
        LocalizedStringResource(value, bundle: bundle)
    }

    /// The table `verbatim(_:)` looks in. No catalog has it, so the lookup always falls back to the
    /// default value.
    static let verbatimTable = "IntentVerbatim"

    /// `text` as a resource that resolves to exactly `text` in every language. A dialog literal such
    /// as `"\(message)"` is an app-bundle lookup of the key `%@`, which only showed the text because
    /// no catalog had that key. Built without a literal, so Xcode extracts nothing into a catalog.
    /// See CODE_AUDIT_Since_3.0.1 §4.1.
    static func verbatim(_ text: String) -> LocalizedStringResource {
        var interpolation = String.LocalizationValue.StringInterpolation(literalCapacity: 0, interpolationCount: 1)
        interpolation.appendInterpolation(text)
        return LocalizedStringResource(
            String.LocalizationValue(stringInterpolation: interpolation),
            table: verbatimTable,
            bundle: .module
        )
    }
}
