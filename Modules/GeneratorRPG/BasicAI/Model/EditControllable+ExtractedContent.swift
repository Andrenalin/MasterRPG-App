// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import Foundation

public extension EditControllable {
    /// Applies the selected fields of an extraction as one edit: one save, one CloudKit export
    /// and one undo step per item instead of three. Shared by Adventure, Character, Map and
    /// Table, which each had a copy. See CODE_AUDIT_29 §7.8, §9.2.
    /// `forceSave` is `true` from the editor's extraction, which persists also during a game.
    @MainActor func applyExtractedContent(_ content: TableSummaryAnalysis, to itemId: UUID, selection: TextSummaryPropertySelection, forceSave: Bool) {
        guard selection.applyTitle || selection.applyDescription || selection.applyTags else { return }
        reset(
            name: selection.applyTitle ? content.title : nil,
            description: selection.applyDescription ? content.description : nil,
            tags: selection.applyTags ? content.tags : nil,
            itemId: itemId,
            forceSave: forceSave
        )
    }
}
#endif
