// @copyright André Trettin

import SwiftUI

public struct ZoomTransitionViewModifier: ViewModifier {
    public init(sourceID: String, namespace: Namespace.ID) {
        self.sourceID = sourceID
        self.namespace = namespace
    }
    
    let sourceID: String
    let namespace: Namespace.ID
    
    public func body(content: Content) -> some View {
        content
#if os(macOS)
            .navigationTransition(.automatic)
#else
            .navigationTransition(.zoom(sourceID: sourceID, in: namespace))
#endif
    }
}

public struct ZoomDestinationViewModifier: ViewModifier {
    public init(sourceID: String, namespace: Namespace.ID) {
        self.sourceID = sourceID
        self.namespace = namespace
    }
    
    let sourceID: String
    let namespace: Namespace.ID
    
    public func body(content: Content) -> some View {
        content
            .matchedTransitionSource(id: sourceID, in: namespace)
    }
}
