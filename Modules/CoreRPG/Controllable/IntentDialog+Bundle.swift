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
}

public extension LocalizedStringResource {
    /// A runtime string of an intent (a dialog part, an error) localized from `bundle`.
    /// See `IntentDialog.localized(_:bundle:)`.
    static func intent(_ value: String.LocalizationValue, bundle: Bundle) -> LocalizedStringResource {
        LocalizedStringResource(value, bundle: bundle)
    }
}
