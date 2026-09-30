// @copyright André Trettin

import Foundation

enum EditorFocus {
    /// Lets an editor's presentation animation finish before it grabs keyboard focus —
    /// focusing mid-transition reads as a glitch. Shared by the item header and entry editors,
    /// which declared it twice. See CODE_AUDIT §9.14, CODE_AUDIT_19 §9.25.
    static let autoFocusDelay: Duration = .milliseconds(100)
}
