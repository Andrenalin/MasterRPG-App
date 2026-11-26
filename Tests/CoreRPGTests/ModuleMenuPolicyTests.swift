// @copyright André Trettin

#if canImport(Testing) && !os(tvOS)
import Foundation
import Testing

@testable import CoreRPG

@Suite("Module menu policy")
struct ModuleMenuPolicyTests {
    // CODE_AUDIT_28 §5.12
    @Test("Fit to Window does not share Command-0 with Show Weather")
    func fitToWindowHasItsOwnShortcut() {
        #expect(!ModuleMenuPolicy.fitToWindowCollidesWithShowModule)
    }

    @Test("Delete takes the selected row, or the checked rows in selection mode")
    func deleteRows() {
        let selected = UUID()
        let checked = [UUID(), UUID()]

        let single = ModuleMenuPolicy.deleteRowIds(isSelectionMode: false, selection: checked, selected: selected)
        #expect(single == [selected])
        #expect(ModuleMenuPolicy.isDeleteEnabled(rowIds: single))

        let many = ModuleMenuPolicy.deleteRowIds(isSelectionMode: true, selection: checked, selected: selected)
        #expect(many == checked)
        #expect(ModuleMenuPolicy.isDeleteEnabled(rowIds: many))

        #expect(!ModuleMenuPolicy.isDeleteEnabled(rowIds: ModuleMenuPolicy.deleteRowIds(isSelectionMode: false, selection: [], selected: nil)))
        #expect(!ModuleMenuPolicy.isDeleteEnabled(rowIds: ModuleMenuPolicy.deleteRowIds(isSelectionMode: true, selection: [], selected: selected)))
    }
}
#endif
