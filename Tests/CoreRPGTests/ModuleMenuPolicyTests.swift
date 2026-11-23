// @copyright André Trettin

#if canImport(Testing) && !os(tvOS)
import Testing

@testable import CoreRPG

@Suite("Module menu policy")
struct ModuleMenuPolicyTests {
    // CODE_AUDIT_28 §5.12
    @Test("Fit to Window does not share Command-0 with Show Weather")
    func fitToWindowHasItsOwnShortcut() {
        #expect(!ModuleMenuPolicy.fitToWindowCollidesWithShowModule)
    }

    // CODE_AUDIT_28 §5.13
    @Test("Delete is only enabled with a selection and the list focused")
    func deleteNeedsListFocus() {
        #expect(ModuleMenuPolicy.isDeleteEnabled(hasSelection: true, isListFocused: true))
        #expect(!ModuleMenuPolicy.isDeleteEnabled(hasSelection: true, isListFocused: false))
        #expect(!ModuleMenuPolicy.isDeleteEnabled(hasSelection: false, isListFocused: true))
    }
}
#endif
