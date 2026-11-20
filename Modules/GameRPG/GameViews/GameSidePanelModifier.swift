// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Where a side panel sits in the sidebar. The split layouts (see `GameSidebarLayout`) lay two
/// panels out in one sidebar, and the panels adapt their safe-area handling to their slot.
enum GameSidePanelSlot {
    /// The whole sidebar column.
    case full
    /// The upper half of the horizontal layout.
    case top
    /// The lower half of the horizontal layout.
    case bottom
    /// The leading column of the vertical layout.
    case leading
    /// The trailing column of the vertical layout.
    case trailing

    /// The slot reaches the top screen edge, so its content clears the top safe area.
    var touchesTopEdge: Bool {
        self != .bottom
    }

    /// The slot reaches the trailing screen edge.
    var touchesTrailingEdge: Bool {
        self != .leading
    }

    /// The slot reaches the bottom screen edge, where the quick dice overlay can sit.
    var touchesBottomEdge: Bool {
        self != .top
    }
}

extension EnvironmentValues {
    @Entry var gameSidePanelSlot: GameSidePanelSlot = .full
}

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
    /// iPhone Duo). On tvOS the top menu's buttons always lie over the panel, so its
    /// content always starts below them.
    func gameSidePanelContent() -> some View {
#if os(iOS) || os(tvOS)
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

#if os(iOS) || os(tvOS)
private struct GameSidePanelContentModifier: ViewModifier {
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.gameSidePanelSlot) private var slot
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
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
    /// The tvOS menu spans the screen, so it always overlaps the panel.
    private var topInset: CGFloat {
        guard let systemTopInset, slot.touchesTopEdge else { return 0 }
#if os(iOS)
        let contentTop = horizontalSizeClass == .compact
            ? gameScreenModel.sidePanelContentTop
            : gameScreenModel.chromeTopSafeAreaInset
#else
        let contentTop = gameScreenModel.sidePanelContentTop
#endif
        return max(0, contentTop - systemTopInset)
    }
}
#endif

#if os(iOS)
private struct GameSidePanelTrailingSafeAreaModifier: ViewModifier {
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.gameSidePanelSlot) private var slot

    func body(content: Content) -> some View {
        content
            .padding(.trailing, slot.touchesTrailingEdge ? -gameScreenModel.chromeTrailingSafeAreaInset : 0)
    }
}
#endif

private struct GameSidePanelModifier<Value: Equatable>: ViewModifier {
    let isShown: Bool
    let width: CGFloat
    let animationValue: Value
    let onWidthChange: (@MainActor (CGFloat) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.gameSidePanelSlot) private var slot

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
            // Outside the background, so the panel itself ends above the quick dice overlay.
            .padding(.bottom, slot.touchesBottomEdge ? gameScreenModel.quickDiceBottomReservation : 0)
            .offset(
                x: isShown
                    ? 0
                    : content.valueFor(iOS: width, macOS: width, tvOS: width, visionOS: -width)
            )
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
            .disabled(!isShown)
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
