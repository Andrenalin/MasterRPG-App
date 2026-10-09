// @copyright André Trettin

import GameController
import SwiftUI

// The map editor's popover: a glass panel with an arrow pointing at its source,
// used for the pin actions (`MapPinActionMenuStack`) and the needle actions.

/// Presents `content` in a popover-styled glass panel next to `source`.
///
/// The panel is drawn in viewport space instead of using a system popover. A
/// system popover is modal: the first tap or drag outside it dismisses it and
/// is swallowed. This panel stays open while the canvas pans or zooms and
/// follows its source; a tap on the canvas still closes it through the canvas'
/// regular selection handling.
struct MapPopover<Content: View>: View {
    /// The source's frame in viewport coordinates.
    let source: CGRect
    /// The unobscured viewport area the panel must stay inside.
    let viewportRectangle: CGRect
    /// The sides of the source to try, in order.
    var preferredSides: [MapPopoverSide] = MapPopoverSide.allCases
    /// Closes the panel. Called by Escape (the Menu button on tvOS), which a
    /// system popover would handle itself.
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    @State private var contentSize = CGSize.zero

    var body: some View {
        let placement = MapPopoverGeometry.placement(
            source: source,
            contentSize: contentSize,
            viewport: viewportRectangle,
            preferredSides: preferredSides
        )
        let shape = MapPopoverShape(side: placement.side, arrowOffset: placement.arrowOffset)

        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                contentSize = size
            }
            .padding(Edge.Set(placement.side.arrowEdge), MapPopoverGeometry.arrowLength)
            // Taps between the buttons must not fall through and clear the
            // selection on the canvas.
            .contentShape(shape)
            .modifier(MapPopoverPanelBackground(shape: shape))
            .opacity(placement.isValid ? 1 : 0)
            .position(x: placement.frame.midX, y: placement.frame.midY)
            .modifier(MapPopoverDismissal(onDismiss: onDismiss))
    }
}

#if os(visionOS)
/// The popover panel as a RealityKit attachment standing above its source, for a map surface
/// in a volume (GameRPG's 3D table). A volume has no viewport to place the panel in, so the
/// arrow stays at the center of the bottom edge and the owner positions the attachment with
/// the arrow's tip at the source.
struct MapPopoverAttachment<Content: View>: View {
    /// Closes the panel from the keyboard. `nil` for a panel that is not dismissed: it does
    /// not take the focus.
    var onDismiss: (() -> Void)?
    /// Whether a panel without `onDismiss` takes taps. One that only shows something lets them
    /// through to the table behind it.
    var isInteractive = false
    @ViewBuilder let content: Content

    var body: some View {
        let shape = MapPopoverShape(side: .top, arrowOffset: nil)
        let panel = content
            .fixedSize()
            .padding(.bottom, MapPopoverGeometry.arrowLength)
            .contentShape(shape)
            // The system glass, unlike in `MapPopoverPanelBackground`: nothing clips an
            // attachment, and a material without a window behind it is all but invisible.
            .glassBackgroundEffect(in: shape)

        if let onDismiss {
            panel.modifier(MapPopoverDismissal(onDismiss: onDismiss))
        } else {
            panel.allowsHitTesting(isInteractive)
        }
    }
}
#endif

/// The panel's glass: Liquid Glass, and a material on visionOS, where Liquid Glass is
/// unavailable.
private struct MapPopoverPanelBackground: ViewModifier {
    let shape: MapPopoverShape

    func body(content: Content) -> some View {
#if os(visionOS)
        // Not `glassBackgroundEffect`: the system glass is its own 3D layer. Inside the
        // canvas' clip it stays at the viewport origin instead of following its source, and
        // the buttons on it are not drawn.
        content.background(.regularMaterial, in: shape)
#elseif os(tvOS)
        // The section lets the focus engine reach the panel from a source that is not
        // directly in line with it.
        content
            .glassEffect(.regular, in: shape)
            .focusSection()
#else
        content.glassEffect(.regular, in: shape)
#endif
    }
}

/// Closes the panel from the keyboard or the remote, as a system popover does.
private struct MapPopoverDismissal: ViewModifier {
    let onDismiss: () -> Void

#if os(macOS)
    private static let hasHardwareKeyboard = true
#elseif !os(tvOS)
    private static var hasHardwareKeyboard: Bool { GCKeyboard.coalesced != nil }
#endif

#if !os(tvOS)
    @FocusState private var isFocused: Bool
#endif

    func body(content: Content) -> some View {
#if os(tvOS)
        // The focus engine has to land on the buttons, so the panel itself must not be
        // focusable; the Menu button closes it while one of them is focused.
        content.onExitCommand(perform: onDismiss)
#else
        // Escape closes the panel on macOS and with a hardware keyboard on iPad and
        // visionOS, as it does a system popover. See CODE_AUDIT_20 §8.5.
        content
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.escape) {
                onDismiss()
                return .handled
            }
            .task {
                // Only where a key can be pressed. Taken unconditionally, the focus left a text
                // field that was being edited as soon as a pin was selected, and with it the
                // on-screen keyboard. See CODE_AUDIT_21 §8.4.
                guard Self.hasHardwareKeyboard else { return }
                isFocused = true
            }
#endif
    }
}

/// A rounded panel with an arrow on the edge facing the popover's source.
struct MapPopoverShape: InsettableShape {
    let side: MapPopoverSide
    /// The arrow tip's position along its edge; `nil` centers it.
    let arrowOffset: CGFloat?
    var cornerRadius: CGFloat = MapPopoverGeometry.cornerRadius
    var arrowLength: CGFloat = MapPopoverGeometry.arrowLength
    var arrowWidth: CGFloat = MapPopoverGeometry.arrowWidth
    /// Insets the whole outline, the arrow included. The system glass on visionOS asks for it.
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> MapPopoverShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let edge = side.arrowEdge
        let body = CGRect(
            x: rect.minX + (edge == .leading ? arrowLength : 0),
            y: rect.minY + (edge == .top ? arrowLength : 0),
            width: rect.width - (side.isHorizontal ? arrowLength : 0),
            height: rect.height - (side.isHorizontal ? 0 : arrowLength)
        )
        let radius = max(0, min(cornerRadius, body.width / 2, body.height / 2))
        let halfWidth = arrowWidth / 2
        let tipX = body.minX + (arrowOffset ?? body.width / 2)
        let tipY = body.minY + (arrowOffset ?? body.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        if edge == .top {
            path.addLine(to: CGPoint(x: tipX - halfWidth, y: body.minY))
            path.addLine(to: CGPoint(x: tipX, y: body.minY - arrowLength))
            path.addLine(to: CGPoint(x: tipX + halfWidth, y: body.minY))
        }
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.minY),
            tangent2End: CGPoint(x: body.maxX, y: body.maxY),
            radius: radius
        )
        if edge == .trailing {
            path.addLine(to: CGPoint(x: body.maxX, y: tipY - halfWidth))
            path.addLine(to: CGPoint(x: body.maxX + arrowLength, y: tipY))
            path.addLine(to: CGPoint(x: body.maxX, y: tipY + halfWidth))
        }
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.maxY),
            tangent2End: CGPoint(x: body.minX, y: body.maxY),
            radius: radius
        )
        if edge == .bottom {
            path.addLine(to: CGPoint(x: tipX + halfWidth, y: body.maxY))
            path.addLine(to: CGPoint(x: tipX, y: body.maxY + arrowLength))
            path.addLine(to: CGPoint(x: tipX - halfWidth, y: body.maxY))
        }
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.maxY),
            tangent2End: CGPoint(x: body.minX, y: body.minY),
            radius: radius
        )
        if edge == .leading {
            path.addLine(to: CGPoint(x: body.minX, y: tipY + halfWidth))
            path.addLine(to: CGPoint(x: body.minX - arrowLength, y: tipY))
            path.addLine(to: CGPoint(x: body.minX, y: tipY - halfWidth))
        }
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.minY),
            tangent2End: CGPoint(x: body.maxX, y: body.minY),
            radius: radius
        )
        path.closeSubpath()
        return path
    }
}

private extension MapPopoverSide {
    /// The panel edge that carries the arrow, facing the source.
    var arrowEdge: Edge {
        switch self {
        case .trailing: .leading
        case .leading: .trailing
        case .bottom: .top
        case .top: .bottom
        }
    }
}

extension CGRect {
    /// The part of a viewport of `size` that a popover may use. System bars and visionOS
    /// ornaments can visually cover a full-screen map without belonging to its hit-test
    /// tree, so viewport controls are placed only in the unobscured rectangle.
    static func unobscuredViewport(size: CGSize, safeAreaInsets: EdgeInsets) -> CGRect {
        func safeInset(_ value: CGFloat) -> CGFloat {
            value.isFinite ? max(0, value) : 0
        }
        let viewport = CGRect(origin: .zero, size: size)
        let top = safeInset(safeAreaInsets.top)
        let leading = safeInset(safeAreaInsets.leading)
        let bottom = safeInset(safeAreaInsets.bottom)
        let trailing = safeInset(safeAreaInsets.trailing)
        let rectangle = CGRect(
            x: viewport.minX + leading,
            y: viewport.minY + top,
            width: viewport.width - leading - trailing,
            height: viewport.height - top - bottom
        )
        guard rectangle.width > 0, rectangle.height > 0 else {
            return viewport
        }
        return rectangle
    }
}

/// A circular action button for a `MapPopover` panel.
struct MapPopoverButton: View {
    let title: Text
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
            .labelStyle(.iconOnly)
            .imageScale(.large)
            .modifier(MapPopoverButtonSize())
            .contentShape(.circle)
        }
        .modifier(MapPopoverButtonAppearance(tint: tint))
        .help(title)
    }
}

/// One size for every button of a panel. Sized by its symbol, a trash button came out larger
/// than a plus button and both stayed below the 44 pt touch target, with the destructive action
/// next to its neighbour. The diameter follows Dynamic Type. tvOS and visionOS keep the padding:
/// their bordered style sizes the button. See CODE_AUDIT_21 §8.1.
private struct MapPopoverButtonSize: ViewModifier {
#if os(macOS)
    private static let baseDiameter: CGFloat = 36
#else
    private static let baseDiameter: CGFloat = 44
#endif

    @ScaledMetric(relativeTo: .body) private var diameter = MapPopoverButtonSize.baseDiameter

    func body(content: Content) -> some View {
#if os(tvOS) || os(visionOS)
        content.padding(MapPopoverLayout.contentInset)
#else
        content.frame(width: diameter, height: diameter)
#endif
    }
}

/// Flat tinted circles inside the (already glass) popover panel. tvOS and visionOS use the
/// bordered button style, whose focus and hover feedback comes from the style.
private struct MapPopoverButtonAppearance: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
#if os(tvOS) || os(visionOS)
        content
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(tint)
#else
        content
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(tint.opacity(0.7), in: .circle)
#endif
    }
}

#Preview("Map popover row") {
    let viewport = CGRect(x: 0, y: 0, width: 360, height: 420)
    // Sources shaped like a needle: room above the first, none above the second.
    let sources = [
        CGRect(x: 60, y: 220, width: 44, height: 110),
        CGRect(x: 250, y: 20, width: 44, height: 110)
    ]
    ZStack(alignment: .topLeading) {
        ForEach(sources, id: \.origin.x) { source in
            Rectangle()
                .stroke(.white)
                .frame(width: source.width, height: source.height)
                .position(x: source.midX, y: source.midY)
            MapPopover(
                source: source,
                viewportRectangle: viewport,
                preferredSides: [.top, .bottom],
                onDismiss: {}
            ) {
                HStack(spacing: 8) {
                    MapPopoverButton(title: Text(verbatim: "Remove"), systemImage: "trash", tint: .red) {}
                    MapPopoverButton(title: Text(verbatim: "Add"), systemImage: "plus", tint: .teal) {}
                }
                .padding(8)
            }
        }
    }
    .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
    .background(Color.blue.gradient)
}
