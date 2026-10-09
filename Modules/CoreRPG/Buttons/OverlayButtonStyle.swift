// @copyright André Trettin

import SwiftUI

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
            .imageScale(.large)
            .padding(8)
            .glassEffect(glass, in: .circle)
            // Keeps the compact glass size but hit-tests at least 44×44 pt (HIG).
            .minimumHitArea()
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
            .imageScale(.large)
            .padding(8)
            .glassEffect(glass, in: .capsule)
            // Keeps the compact glass size but hit-tests at least 44×44 pt (HIG).
            .minimumHitArea()
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
