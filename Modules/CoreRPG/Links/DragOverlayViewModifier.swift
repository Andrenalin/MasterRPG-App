// @copyright André Trettin

import SwiftUI

extension View {
    public func draggableWithOverlay(for module: NetworkModules, itemId: UUID, entryId: UUID?, name: String, isMove: Bool = false) -> some View {
        modifier(DragOverlayViewModifier(module: module, itemId: itemId, entryId: entryId, name: name))
    }
}

struct DragOverlayViewModifier: ViewModifier {
    let module: NetworkModules
    let itemId: UUID
    let entryId: UUID?
    let name: String
    
    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
#if os(macOS)
            .textSelection(.disabled)
            .overlay {
                // Color.primary.opacity(0.001) gives AppKit a non-text surface to initiate drag from,
                // which text-only rows lack even with textSelection disabled.
                Color.primary.opacity(0.001)
                    .draggable(for: module, itemId: itemId, entryId: entryId, name: name)
            }
#else
            .draggable(for: module, itemId: itemId, entryId: entryId, name: name)
#endif
    }
}
