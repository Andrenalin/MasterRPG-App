// @copyright André Trettin

import CoreGraphics

/// Named layout constants for the table-generation panel feature, replacing
/// several previously-unexplained magic numbers scattered across its views.
/// See CODE_AUDIT_Table §8.3.
enum TableGenerationLayout {
    /// `TableGenerationEntryRow`'s selection card.
    static let cardRadius: CGFloat = 16
    /// `TableGenerationOccurrenceView`'s occurrence group background.
    static let groupRadius: CGFloat = 20
    /// `TableGenerationPanelView`'s outer panel shell.
    static let panelRadius: CGFloat = 28

    /// Apple HIG minimum tap target height, used by the compact outcome row.
    static let minTouchTargetHeight: CGFloat = 44

    /// `TableGenerationPanelView`'s fixed panel size.
    static let panelWidth: CGFloat = 760
    static let panelHeight: CGFloat = 820
}
