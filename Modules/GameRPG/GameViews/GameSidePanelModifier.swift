// @copyright André Trettin

import CoreRPG
import SwiftUI

extension View {
    /// The game screen's slide-in side panel: sidebar width, material background, and the slide,
    /// fade and hit-testing of a hidden panel. Shared by the main tab (game master and player)
    /// and the module list, which had three copies. See CODE_AUDIT_19 §9.19.
    ///
    /// - Parameter onWidthChange: Reports the panel's rendered width, for panels the screen
    ///   lays other content out around.
    func gameSidePanel<Value: Equatable>(
        isShown: Bool,
        width: CGFloat,
        animationValue: Value,
        onWidthChange: (@MainActor (CGFloat) -> Void)? = nil
    ) -> some View {
        modifier(GameSidePanelModifier(
            isShown: isShown,
            width: width,
            animationValue: animationValue,
            onWidthChange: onWidthChange
        ))
    }

    /// For a side panel's content (the root view of its navigation stack, or the content
    /// itself where there is no stack): keeps it inside the top safe area and, in the
    /// compact layout, below the top menu wherever the status bar and navigation bar don't
    /// already clear it (no top safe area and no or a compact navigation bar, as on
    /// iPhone Duo).
    func gameSidePanelContent() -> some View {
#if os(iOS)
        modifier(GameSidePanelContentModifier())
#else
        self
#endif
    }

    /// Lets a side panel's navigation stack run past the trailing screen edge by the
    /// trailing safe-area inset. UIKit hands the stack the window's full inset wherever the
    /// panel sits, so this is what lets its content span the whole panel. Apply it to the
    /// navigation stack itself: other content is not inset and would be pushed off screen.
    func gameSidePanelIgnoringTrailingSafeArea() -> some View {
#if os(iOS)
        modifier(GameSidePanelTrailingSafeAreaModifier())
#else
        self
#endif
    }
}

#if os(iOS)
private struct GameSidePanelContentModifier: ViewModifier {
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var systemTopInset: CGFloat?

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.top, topInset)
            // Measured outside the padding above: the inset the status bar and the
            // navigation bar provide on their own. The panel starts at the screen's top edge.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.top
            } action: { inset in
                systemTopInset = inset
            }
    }

    /// The top menu only overlaps the panel in the compact layout; in the regular one it
    /// ends at the panel's leading edge and the content only has to clear the safe area.
    private var topInset: CGFloat {
        guard let systemTopInset else { return 0 }
        let contentTop = horizontalSizeClass == .compact
            ? gameScreenModel.sidePanelContentTop
            : gameScreenModel.chromeTopSafeAreaInset
        return max(0, contentTop - systemTopInset)
    }
}

private struct GameSidePanelTrailingSafeAreaModifier: ViewModifier {
    @Environment(GameScreenModel.self) private var gameScreenModel

    func body(content: Content) -> some View {
        content
            .padding(.trailing, -gameScreenModel.chromeTrailingSafeAreaInset)
    }
}
#endif

private struct GameSidePanelModifier<Value: Equatable>: ViewModifier {
    let isShown: Bool
    let width: CGFloat
    let animationValue: Value
    let onWidthChange: (@MainActor (CGFloat) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func body(content: Content) -> some View {
        content
            .frame(
                maxWidth: width,
                maxHeight: .infinity,
                alignment: content.valueFor(iOS: .trailing, macOS: .trailing, tvOS: .trailing, visionOS: .leading)
            )
#if os(iOS)
            .ignoresSafeArea()
            .clipShape(Self.iOSPanelShape)
            .background(.ultraThinMaterial, in: Self.iOSPanelShape)
#elseif !os(visionOS)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: ResolvedAppTheme.panelCornerRadius))
#endif
            .offset(
                x: isShown
                    ? 0
                    : content.valueFor(iOS: width, macOS: width, tvOS: width, visionOS: -width)
            )
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
            .shadow(radius: 8)
            .animation(accessibilityReduceMotion ? nil : .bouncy, value: animationValue)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                onWidthChange?(width)
            }
    }

#if os(iOS)
    /// Rounded only on the leading edge: the panel slides in from the trailing screen edge.
    private static var iOSPanelShape: UnevenRoundedRectangle {
        .rect(topLeadingRadius: 14, bottomLeadingRadius: 14, bottomTrailingRadius: 0, topTrailingRadius: 0)
    }
#endif
}
