// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
/// The shortcut and enablement decisions of the module menu commands that can be unit-tested
/// without a menu bar.
enum ModuleMenuPolicy {
    /// The modules' "Show <Module>" commands use Command + a digit, Weather's the 0. The map
    /// editor's "Fit to Window" must not share it: with two items on one shortcut either the
    /// zoom reset did nothing or the app jumped to Weather. See CODE_AUDIT_28 §5.12.
    static let fitToWindowKey: KeyEquivalent = "0"
    static let fitToWindowModifiers: EventModifiers = [.command, .option]
    static let showModuleModifiers: EventModifiers = [.command]

    static var fitToWindowCollidesWithShowModule: Bool {
        fitToWindowModifiers == showModuleModifiers
    }

    /// Command-Delete is also "delete to start of line" in a text field, so the menu command
    /// only acts while the module list has the focus, like Space and Return.
    /// See CODE_AUDIT_28 §5.13.
    static func isDeleteEnabled(hasSelection: Bool, isListFocused: Bool) -> Bool {
        hasSelection && isListFocused
    }
}
#endif
