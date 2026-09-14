// @copyright André Trettin

import SwiftUI

#Preview {
    HStack {
        ImageOverlayButton(
            icon: "pencil",
            accessibilityLabel: LocalizedStringResource("Edit", bundle: .module),
            action: {}
        )
        ImageOverlayButton(
            icon: "trash",
            accessibilityLabel: LocalizedStringResource("Delete", bundle: .module),
            disabled: true,
            action: {}
        )
    }
}

public struct ImageOverlayButton: View {
    public init(
        icon: String,
        accessibilityLabel: LocalizedStringResource,
        disabled: Bool = false,
        withoutButton: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.disabled = disabled
        self.withoutButton = withoutButton
        self.action = action
    }
    
    let icon: String
    let accessibilityLabel: LocalizedStringResource
    let disabled: Bool
    let withoutButton: Bool
    let action: () -> Void
    
    public var body: some View {
        if withoutButton {
            ImageOverlayButtonImageView(icon: icon, disabled: disabled)
                .accessibilityLabel(Text(accessibilityLabel))
        } else {
            Button(action: action) {
                Label {
                    Text(accessibilityLabel)
                } icon: {
                    ImageOverlayButtonImageView(icon: icon, disabled: disabled)
                }
                .labelStyle(.iconOnly)
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
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct ImageOverlayButtonImageView: View {
    let icon: String
    let disabled: Bool

    var body: some View {
        Image(systemName: icon)
#if os(iOS) || os(visionOS)
            .imageScale(.medium)
            .padding(8)
#if os(iOS)
            .foregroundStyle(disabled ? Color.secondary : Color.teal)
            .hoverEffect(.highlight, isEnabled: !disabled)
            // `.glassEffectAll` composits shape/shadow internally, replacing the previous
            // `.background(.ultraThinMaterial)` + `.clipShape` + `.shadow` chain. See CODE_AUDIT_9 §8.5.
            .glassEffectAll(.regular, in: .circle)
#else
            .clipShape(.circle)
            .shadow(color: .primary, radius: 4)
#endif
#endif
    }
}
