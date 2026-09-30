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
}

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
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
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
