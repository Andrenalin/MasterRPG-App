// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

// Pin action menu in the style of the game master's side menu
// (`MasterModuleWindowMenu`): circular buttons in a popover-styled glass panel
// pointing at the pin, on every platform. The actions are the same as
// `MapPinActionContext.actions`.

/// Presents the expanded pin's actions in a popover-styled glass panel.
///
/// The panel is drawn in viewport space instead of using a system popover. A
/// system popover is modal: the first tap or drag outside it dismisses it and
/// is swallowed. This panel stays open while the canvas pans or zooms and
/// follows its pin; a tap on the canvas still closes it through the canvas'
/// regular selection handling.
struct MapPinActionPopover: View {
    let model: MapPinNode
    let context: MapPinActionContext
    /// The pin's frame in viewport coordinates.
    let source: CGRect
    /// The unobscured viewport area the panel must stay inside.
    let viewportRectangle: CGRect
    /// Closes the panel. Called by Escape (the Menu button on tvOS), which a
    /// system popover would handle itself.
    let onDismiss: () -> Void

    @State private var contentSize = CGSize.zero

    var body: some View {
        let placement = MapPopoverGeometry.placement(
            source: source,
            contentSize: contentSize,
            viewport: viewportRectangle
        )
        let shape = MapPopoverShape(side: placement.side, arrowOffset: placement.arrowOffset)

        MapPinActionMenuStack(model: model, context: context)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                contentSize = size
            }
            .padding(Edge.Set(placement.side.arrowEdge), MapPopoverGeometry.arrowLength)
            // Taps between the buttons must not fall through and clear the
            // pin selection on the canvas.
            .contentShape(shape)
            .modifier(MapPopoverPanelBackground(shape: shape))
            .opacity(placement.isValid ? 1 : 0)
            .position(x: placement.frame.midX, y: placement.frame.midY)
            .modifier(MapPopoverDismissal(onDismiss: onDismiss))
    }
}

/// The panel's glass: Liquid Glass, and a material on visionOS, where Liquid Glass is
/// unavailable.
private struct MapPopoverPanelBackground: ViewModifier {
    let shape: MapPopoverShape

    func body(content: Content) -> some View {
#if os(visionOS)
        // Not `glassBackgroundEffect`: the system glass is its own 3D layer. Inside the
        // canvas' clip it stays at the viewport origin instead of following the pin, and
        // the buttons on it are not drawn.
        content.background(.regularMaterial, in: shape)
#elseif os(tvOS)
        // The section lets the focus engine reach the panel from a pin that is not
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
            .task { isFocused = true }
#endif
    }
}

/// A rounded panel with an arrow on the edge facing the popover's source.
struct MapPopoverShape: Shape {
    let side: MapPopoverSide
    let arrowOffset: CGFloat
    var cornerRadius: CGFloat = MapPopoverGeometry.cornerRadius
    var arrowLength: CGFloat = MapPopoverGeometry.arrowLength
    var arrowWidth: CGFloat = MapPopoverGeometry.arrowWidth

    func path(in rect: CGRect) -> Path {
        let edge = side.arrowEdge
        let body = CGRect(
            x: rect.minX + (edge == .leading ? arrowLength : 0),
            y: rect.minY + (edge == .top ? arrowLength : 0),
            width: rect.width - (side.isHorizontal ? arrowLength : 0),
            height: rect.height - (side.isHorizontal ? 0 : arrowLength)
        )
        let radius = max(0, min(cornerRadius, body.width / 2, body.height / 2))
        let halfWidth = arrowWidth / 2
        let tipX = body.minX + arrowOffset
        let tipY = body.minY + arrowOffset

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

/// A vertical column of pin action buttons, laid out like the master side menu.
struct MapPinActionMenuStack: View {
    let model: MapPinNode
    let context: MapPinActionContext

    @Namespace private var photoSpace

    var body: some View {
        GlassEffectContainerAll {
            VStack(spacing: 8) {
                ForEach(context.actions, id: \.self) { type in
                    // The panel is glass already: flat buttons, no glass inside glass.
                    MapPinActionMenuButton(
                        model: model,
                        type: type,
                        context: context,
                        photoSpace: photoSpace
                    )
                }
            }
        }
        // Half of the default `padding()` inset.
        .padding(8)
        .modifier(
            MapPinPhotoSelectionModifier(
                model: model,
                context: context,
                photoSpace: photoSpace
            )
        )
    }
}

struct MapPinActionMenuButton: View {
    let model: MapPinNode
    let type: MapPinButtonType
    let context: MapPinActionContext
    let photoSpace: Namespace.ID

    private var pin: MapPinModel { model.pin }

    var body: some View {
        Button {
            model.perform(type, context: context)
        } label: {
            Label {
                Text(type.localizedLabel(for: pin))
            } icon: {
                Image(systemName: type.systemImage(for: pin))
            }
            .labelStyle(.iconOnly)
            .imageScale(.large)
            .padding(8)
            .contentShape(.circle)
        }
        .modifier(MapPinActionButtonAppearance(tint: type.tint(for: pin)))
        .help(Text(type.localizedLabel(for: pin)))
        .applyIf(type == .photo) {
            $0.matchedTransitionSource(id: type.label, in: photoSpace)
        }
    }
}

/// Flat tinted circles inside the (already glass) popover panel. tvOS and visionOS use the
/// bordered button style, whose focus and hover feedback comes from the style.
private struct MapPinActionButtonAppearance: ViewModifier {
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

/// Presents the photo picker for the editor's "Choose Pin Photo" action and
/// writes the selection back into the pin.
struct MapPinPhotoSelectionModifier: ViewModifier {
    let model: MapPinNode
    let context: MapPinActionContext
    let photoSpace: Namespace.ID

    @Environment(MapRootModel.self) private var root
#if os(macOS)
    @Environment(ScenesManager.self) private var scenesManager
#endif

    @State private var selectedPhoto = ItemSelectionModel(isSingleSelection: true, allowCollections: false)

    func body(content: Content) -> some View {
        @Bindable var model = model

        content
#if os(macOS)
            .onChange(of: model.isPhotoSelectionPresented) { _, isPresented in
                guard context == .editor, isPresented else { return }
                root.photoRoot.itemSelectionModel = selectedPhoto
                scenesManager.openWindow(SceneId(rawValue: NetworkModules.photo.linkWindowId))
                model.isPhotoSelectionPresented = false
            }
            .onChange(of: selectedPhoto.selection) {
                guard context == .editor, let itemId = selectedPhoto.itemId else { return }
                withAnimation { model.replacePhoto(with: itemId) }
                selectedPhoto.resetSelection(itemId: nil, entryId: nil)
            }
#else
            .sheet(isPresented: context == .editor ? $model.isPhotoSelectionPresented : .constant(false)) {
                ManagedPresentationView {
                    root.viewController.photoSelection(root: root, selectionModel: selectedPhoto)
                        .navigationTransition(.zoom(sourceID: MapPinButtonType.photo.label, in: photoSpace))
                }
            }
            .onChange(of: model.isPhotoSelectionPresented) {
                guard context == .editor,
                      !model.isPhotoSelectionPresented,
                      !selectedPhoto.selection.isEmpty else { return }
                withAnimation { model.replacePhoto(with: selectedPhoto.itemId) }
                selectedPhoto.resetSelection(itemId: nil, entryId: nil)
            }
#endif
    }
}

#Preview("Pin Action Menu", traits: .mockData) {
    @Previewable @State var model = MapPinViewModel(
        mapPins: [.empty(MapModel.previewId)],
        pointer: .empty
    )
    HStack(alignment: .top) {
        MapPinActionMenuStack(model: model.mapPinNodes[0], context: .editor)
        MapPinActionMenuStack(model: model.mapPinNodes[0], context: .gameMaster)
    }
    .background(Color.blue.gradient)
}
