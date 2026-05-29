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
            // Nearly invisible background gives AppKit a non-text pixel surface to initiate drag.
            // An overlay would block tap targets; a background sits below all interactive content.
            .background(Color.primary.opacity(0.001))
#endif
            .draggable(for: module, itemId: itemId, entryId: entryId, name: name)
    }
}
