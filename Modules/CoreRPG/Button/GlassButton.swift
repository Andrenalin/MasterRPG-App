// @copyright André Trettin

import SwiftUI

public struct GlassButton<Content: View>: View {
    public init(isProminent: Bool = false,  action: @escaping () -> Void, @ViewBuilder label: () -> Content) {
        self.isProminet = isProminent
        self.label = label()
        self.action = action
    }
    
    let isProminet: Bool
    let label: Content
    let action: () -> Void
    
    public var body: some View {
        if #available(iOS 26.0, *) {
            if isProminet {
                button
                    .buttonStyle(.glassProminent)
            } else {
                button
                    .buttonStyle(.glass)
            }
        } else {
            Button {
                action()
            } label: {
                label
            }
            .buttonStyle(.imageOverlay)
        }
    }
    
    private var button: some View {
        Button {
            action()
        } label: {
            label
        }
    }
}
