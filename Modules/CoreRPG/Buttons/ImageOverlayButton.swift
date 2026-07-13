// @copyright André Trettin

import SwiftUI

#Preview {
    HStack {
        ImageOverlayButton(icon: "pencil", action: {})
        ImageOverlayButton(icon: "trash", disabled: true, action: {})
    }
}

public struct ImageOverlayButton: View {
    public init(icon: String, disabled: Bool = false, withoutButton: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.disabled = disabled
        self.withoutButton = withoutButton
        self.action = action
    }
    
    let icon: String
    let disabled: Bool
    let withoutButton: Bool
    let action: () -> Void
    
    public var body: some View {
        if withoutButton {
            buttonImage
        } else {
            Button(action: action) {
                buttonImage
            }
#if os(macOS)
            .applyIf(disabled) { content in
                content.buttonStyle(.bordered)
            }
            .applyIf(!disabled) { content in
                content.buttonStyle(.borderedProminent)
            }
#elseif os(visionOS)
            .buttonStyle(.bordered)
#else
            .borderLessTVBottonStyle()
#endif
        }
    }
    
    private var buttonImage: some View {
        Image(systemName: icon)
#if os(iOS) || os(visionOS)
            .imageScale(.medium)
            .padding(8)
#if os(iOS)
            .background(.ultraThinMaterial)
            .foregroundStyle(disabled ? Color.secondary : Color.teal)
            .hoverEffect(.highlight, isEnabled: !disabled)
#endif
            .clipShape(.circle)
            .shadow(color: .primary, radius: 4)
#endif
    }
}
