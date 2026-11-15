// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AdditionalEntryRow: View, Equatable {
    let source: ItemRowModel
    let entry: any EntryDataAccessible
    let textModel: LinkHighlightTextModel?
    /// Pre-resolved by the caller where available — see `ViewControllable`'s
    /// doc comment / CODE_AUDIT_10 §8.1. Falls back to `itemOrEmpty` when
    /// nil, so this stays correct for any call site not yet updated.
    var resolvedModel: ValueModel? = nil

    /// Computed once at init so `body`, `valueEntry`, and `Equatable` all agree
    /// on the same fallback id within a render — previously a computed `var`
    /// minted a fresh `UUID()` on every access, desyncing the three lookups
    /// and permanently defeating this view's own equatable-based render-skipping.
    /// See CODE_AUDIT_Character §8.1.
    private let entryId: UUID

    init(source: ItemRowModel, entry: any EntryDataAccessible, textModel: LinkHighlightTextModel?, resolvedModel: ValueModel? = nil) {
        self.source = source
        self.entry = entry
        self.textModel = textModel
        self.resolvedModel = resolvedModel
        self.entryId = source.entryId ?? UUID()
    }

    @Environment(CharacterRootModel.self) private var root
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 4) {

                Image(systemName: typeIcon)
                    .imageScale(.small)
                    .foregroundStyle(.foreground, .tint)
                    .accessibilityHidden(true)
                    .padding(4)
                    .background {
                        iconBackgroundShape.stroke(
                            theme.tint(for: root.configurable.module).opacity(0.3)
                        )
                    }

                if let textModel {
                    LinkHighlightTextView(model: textModel)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            EntryListDiceRow(itemId: source.itemId, entryId: entryId)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconBackgroundShape: some Shape {
        .circle
    }

    private var model: ValueModel {
        resolvedModel ?? root.itemController.itemOrEmpty(for: source.itemId)
    }

    private var valueEntry: ValueEntryModel {
        entry as? ValueEntryModel ?? model[entryId]
    }

    private var typeIcon: String {
        guard valueEntry.valueId != nil else {
            return valueEntry.type.icon
        }
        return "square.on.square.squareshape.controlhandles"
    }

    /// Compares what the body shows: the icon follows the entry's type and group link, and the
    /// text follows the text model, so a type change or a new text model redraws the row.
    /// See CODE_AUDIT_26 §8.3.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entryId == rhs.entryId
            && lhs.source == rhs.source
            && lhs.textModel === rhs.textModel
            && Self.iconKey(of: lhs.entry) == Self.iconKey(of: rhs.entry)
    }

    private static func iconKey(of entry: any EntryDataAccessible) -> String {
        guard let valueEntry = entry as? ValueEntryModel else { return "" }
        return "\(valueEntry.type.icon)|\(valueEntry.valueId != nil)"
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(CharacterRootModel.self) var root

    AdditionalEntryRow(source: ItemRowModel(itemId: root.itemController.itemDataModel.items.first!, entryId: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first!).entries[0].id, typeId: .value), entry: ValueEntryModel.empty, textModel: LinkHighlightTextModel(linkControllable: nil, text: "Hello Links", highlightedText: "in", toggler: nil, shareResult: nil, editAction: nil))
}
