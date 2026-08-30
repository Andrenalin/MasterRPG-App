// @copyright André Trettin

import SwiftUI

public struct ImageOverlayButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.largeTitle)
            .padding()
#if os(visionOS)
            .glassBackgroundEffect()
            .hoverEffect(.highlight, isEnabled: true)
#else
            // `.glassEffectAll` composits shape/shadow internally, so the previous manual
            // `.background(.ultraThinMaterial)` + pre-clip `.shadow` (clipped away before it could
            // render) + `.clipShape` + post-clip `.shadow` chain collapses to this one call.
            // See CODE_AUDIT_9 §8.4/§8.5.
            .glassEffectAll(.regular, in: .circle)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
#endif
    }
}

public extension ButtonStyle where Self == ImageOverlayButtonStyle {
    static var imageOverlay: ImageOverlayButtonStyle {
        ImageOverlayButtonStyle()
    }
}

/// Gives controls that float above game content the same physical treatment as
/// the game window and sidebar controls. Keeping this in CoreRPG lets the map,
/// dice, and game modules share one style without introducing module cycles.
public extension View {
    nonisolated func gameOverlayControlStyle(
        isSelected: Bool = false,
        tint: Color = .accentColor
    ) -> some View {
        modifier(
            GameOverlayControlStyleModifier(
                isSelected: isSelected,
                tint: tint
            )
        )
    }

    nonisolated func gameOverlayCapsuleControlStyle(
        isSelected: Bool = false,
        tint: Color = .accentColor
    ) -> some View {
        modifier(
            GameOverlayCapsuleControlStyleModifier(
                isSelected: isSelected,
                tint: tint
            )
        )
    }
}

private struct GameOverlayControlStyleModifier: ViewModifier {
    let isSelected: Bool
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS) || os(macOS)
        content.buttonStyle(
            GameOverlayControlButtonStyle(
                isSelected: isSelected,
                tint: tint
            )
        )
#elseif os(visionOS)
        if isSelected {
            content
                .buttonStyle(.borderedProminent)
                .tint(tint)
        } else {
            content.buttonStyle(.borderedProminent)
        }
#else
        content.buttonStyle(.borderedProminent)
#endif
    }
}

private struct GameOverlayCapsuleControlStyleModifier: ViewModifier {
    let isSelected: Bool
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS) || os(macOS)
        content.buttonStyle(
            GameOverlayCapsuleButtonStyle(
                isSelected: isSelected,
                tint: tint
            )
        )
#elseif os(visionOS)
        if isSelected {
            content
                .buttonStyle(.borderedProminent)
                .tint(tint)
        } else {
            content.buttonStyle(.borderedProminent)
        }
#else
        content.buttonStyle(.borderedProminent)
#endif
    }
}

#if os(iOS) || os(macOS)
private struct GameOverlayControlButtonStyle: ButtonStyle {
    let isSelected: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.circle)
            .glassEffect(glass, in: .circle)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }

    private var glass: Glass {
        if isSelected {
            .regular.tint(tint.opacity(0.65)).interactive()
        } else {
            .regular.interactive()
        }
    }
}

private struct GameOverlayCapsuleButtonStyle: ButtonStyle {
    let isSelected: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(.capsule)
            .glassEffect(glass, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }

    private var glass: Glass {
        if isSelected {
            .regular.tint(tint.opacity(0.65)).interactive()
        } else {
            .regular.interactive()
        }
    }
}
#endif

#Preview {
    Button {} label: {
        Image(systemName: "skew")
    }
    .buttonStyle(.imageOverlay)
    .borderLessTVBottonStyle()
    .tint(Color.accentColor)
    .accentColor(Color.teal)
}
