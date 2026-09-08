// @copyright André Trettin

import SwiftUI

public struct ZoomTransitionViewModifier: ViewModifier {
    public init(sourceId: String, namespace: Namespace.ID) {
        self.sourceId = sourceId
        self.namespace = namespace
    }

    let sourceId: String
    let namespace: Namespace.ID

    public func body(content: Content) -> some View {
        content
#if os(macOS)
            .navigationTransition(.automatic)
#else
            .navigationTransition(.zoom(sourceID: sourceId, in: namespace))
#endif
    }
}

public struct ZoomDestinationViewModifier: ViewModifier {
    public init(sourceId: String, namespace: Namespace.ID) {
        self.sourceId = sourceId
        self.namespace = namespace
    }

    let sourceId: String
    let namespace: Namespace.ID

    public func body(content: Content) -> some View {
        content
            .matchedTransitionSource(id: sourceId, in: namespace)
    }
}
