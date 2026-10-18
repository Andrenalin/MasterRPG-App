// @copyright André Trettin

#if !os(tvOS)
import SwiftUI

/// The grip a battle card is dragged by to reorder the turn list.
///
/// Only this handle starts a drag. With the whole card as the drag source,
/// every button and text field of the card sat inside a drag gesture, next to
/// the card's context menu, its drop targets and its scroll views.
struct BattleRoundDragHandle: View, Equatable {
    let cardId: UUID
    let name: String

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 28

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .frame(minWidth: side, minHeight: side)
            .contentShape(.rect)
            .draggable(BattleEntryDragPayload.string(for: cardId)) {
                Text(verbatim: name)
                    .font(.headline)
                    .padding(BattleRoundSpacing.standard)
                    .background(.regularMaterial, in: .capsule)
            }
            .help(Text("Drag to reorder", bundle: .module))
            // The card offers "Move Earlier/Later in Turn Order" as
            // accessibility actions; a drag grip has no meaning there.
            .accessibilityHidden(true)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cardId == rhs.cardId && lhs.name == rhs.name
    }
}

#Preview("Drag handle") {
    BattleRoundDragHandle(cardId: UUID(), name: "Aria Swiftwind")
        .padding()
}
#endif
