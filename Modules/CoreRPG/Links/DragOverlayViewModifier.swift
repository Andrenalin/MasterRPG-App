// @copyright André Trettin

import SwiftUI

extension View {
    public func draggableWithOverlay<Preview: View>(
        for module: NetworkModules,
        itemId: UUID,
        entryId: UUID?,
        name: String,
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View {
        modifier(DragOverlayViewModifier(module: module, itemId: itemId, entryId: entryId, name: name, preview: preview))
    }

    // Convenience overload — falls back to a text chip preview
    public func draggableWithOverlay(
        for module: NetworkModules,
        itemId: UUID,
        entryId: UUID?,
        name: String
    ) -> some View {
        draggableWithOverlay(for: module, itemId: itemId, entryId: entryId, name: name) {
            Text(name)
                .lineLimit(1)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
        }
    }
}

struct DragOverlayViewModifier<Preview: View>: ViewModifier {
    let module: NetworkModules
    let itemId: UUID
    let entryId: UUID?
    let name: String
    let preview: () -> Preview

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
#if os(macOS)
            .textSelection(.disabled)
#endif
            // A rendered (non-transparent) background layer is required on both macOS and iOS
            // when a LazyVStack row contains only Text. Unlike List (backed by UITableView/NSTableView),
            // LazyVStack rows must provide an explicit pixel surface for the drag interaction to attach to.
            .background(Color.primary.opacity(0.001))
            .draggable(for: module, itemId: itemId, entryId: entryId, name: name, preview: preview)
    }
}
