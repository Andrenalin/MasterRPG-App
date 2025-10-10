// @copyright André Trettin

import SwiftUI

extension View {
    nonisolated public func swipeActionsAll<T>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true, @ViewBuilder content: () -> T) -> some View where T : View {
#if os(tvOS)
        self
#else
        swipeActions(edge: edge, allowsFullSwipe: allowsFullSwipe, content: content)
#endif
    }
    
    nonisolated public func listRowSeparatorAll(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
#if os(tvOS)
        self
#else
        listRowSeparator(visibility, edges: edges)
#endif
        
    }
}
