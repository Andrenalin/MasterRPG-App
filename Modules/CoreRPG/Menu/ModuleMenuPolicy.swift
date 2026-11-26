// @copyright André Trettin

import Foundation
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

    /// The rows the Edit menu's Delete removes: the checked rows in selection mode, the selected
    /// row otherwise. It is enabled as soon as there is one, whether or not the list has the
    /// focus; Command-Delete typed in a text field still goes to the field, see
    /// `TextFieldShortcutForwarding`. (Replaces the focus rule of CODE_AUDIT_28 §5.13.)
    static func deleteRowIds(isSelectionMode: Bool, selection: [UUID], selected: UUID?) -> [UUID] {
        if isSelectionMode { return selection }
        return selected.map { [$0] } ?? []
    }

    static func isDeleteEnabled(rowIds: [UUID]) -> Bool {
        !rowIds.isEmpty
    }
}
#endif
