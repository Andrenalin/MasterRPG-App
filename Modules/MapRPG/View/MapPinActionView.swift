// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

enum MapPinActionContext: Equatable {
    case none
    case editor
    case gameMaster

    var actions: [MapPinButtonType] {
        switch self {
        case .none:
            []
        case .editor:
            [.remove, .copy, .photo, .character, .resize, .dead]
        case .gameMaster:
            [.dead, .visibility, .resize, .highlight, .battle]
        }
    }
}

/// Public because GameRPG's 3D table performs the game master's actions itself; see
/// `ViewController.gamePinActionPopover`.
public enum MapPinButtonType: String, Hashable, Sendable {
    case remove, copy, photo, character, resize, dead, visibility, highlight, battle

    func systemImage(for pin: MapPinModel) -> String {
        switch self {
        case .remove: return "trash"
        case .copy:   return "document.on.document"
        case .photo:  return NetworkModules.photo.icon
        case .character: return NetworkModules.value.icon
        case .resize: return "square.resize"
        case .dead: return pin.isDead ? "heart.fill" : "xmark.circle"
        case .visibility: return pin.isShown ? "eye.slash" : "eye"
        case .highlight: return pin.isHighlighted ? "circle.fill" : "circle"
        case .battle: return "person.badge.plus"
        }
    }

    var label: String { rawValue.capitalized }

    func tint(for pin: MapPinModel) -> Color {
        switch self {
        case .remove: .red
        case .copy: .gray
        case .photo: .purple
        case .character: .mint
        case .resize: .teal
        case .visibility: .blue
        case .dead: pin.isDead ? .green : .red
        case .highlight: .red
        case .battle: .orange
        }
    }

    func localizedLabel(for pin: MapPinModel) -> LocalizedStringResource {
        switch self {
        case .remove: LocalizedStringResource("Remove Pin", bundle: .module)
        case .copy: LocalizedStringResource("Copy Pin", bundle: .module)
        case .photo: LocalizedStringResource("Choose Pin Photo", bundle: .module)
        case .character: LocalizedStringResource("Choose Pin Character", bundle: .module)
        case .resize: LocalizedStringResource("Resize Pin", bundle: .module)
        case .dead:
            pin.isDead
                ? LocalizedStringResource("Revive Pin", bundle: .module)
                : LocalizedStringResource("Mark Pin Dead", bundle: .module)
        case .visibility:
            pin.isShown
                ? LocalizedStringResource("Hide Pin", bundle: .module)
                : LocalizedStringResource("Show Pin", bundle: .module)
        case .highlight:
            pin.isHighlighted
                ? LocalizedStringResource("Remove Pin Highlight", bundle: .module)
                : LocalizedStringResource("Highlight Pin", bundle: .module)
        case .battle:
            LocalizedStringResource("Add Pin to Battle Round", bundle: .module)
        }
    }

}

struct MapPinActionView: View {
    let model: MapPinNode
    let pinScale: CGFloat
    let canDrag: Bool
    let actionContext: MapPinActionContext
    let doubleTapAccessibilityLabel: LocalizedStringResource
    var viewportScale: CGFloat = 1

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var isMoving = false

    private var pin: MapPinModel { model.pin }

    private var pinSize: CGSize {
        pin.size.size * pinScale
    }

    private var location: CGPoint {
        pin.location - (pinSize / 2)
    }

    var body: some View {
        MapPinView(
            model: model,
            pinSize: pinSize,
            canMove: canDrag,
            actionContext: actionContext,
            doubleTapAccessibilityLabel: doubleTapAccessibilityLabel
        )
#if !os(tvOS)
            // Keep the drag recognizer on the pin itself. Attaching it after
            // the overlay made slight movement on an expanded action button
            // drag the token as well.
            .highPriorityGesture(
                dragGesture,
                including: canDrag ? .all : .none
            )
#endif
            .offset(logicalTranslation(dragTranslation))
            .offset(x: location.x, y: location.y)
    }

#if !os(tvOS)
    private var dragGesture: some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(MapViewportCoordinateSpace.name)
        )
            .updating($dragTranslation) { value, state, _ in
                guard canDrag else { return }
                state = value.translation
            }
            .onChanged { _ in
                guard canDrag, !isMoving else { return }
                isMoving = true
                model.beginMove()
            }
            .onEnded { value in
                guard canDrag else { return }
                isMoving = false
                model.move(by: logicalTranslation(value.translation))
            }
    }

#endif

    private func logicalTranslation(_ translation: CGSize) -> CGSize {
        let scale = viewportScale.isFinite && viewportScale > 0 ? viewportScale : 1
        return CGSize(width: translation.width / scale, height: translation.height / scale)
    }
}

#Preview(traits: .mockData) {
    @Previewable @State var model = MapPinViewModel(
        mapPins: [.empty(MapModel.previewId)],
        pointer: .empty
    )
    ZStack {
        Color.blue
        MapPinActionView(
            model: model.mapPinNodes[0],
            pinScale: 1,
            canDrag: true,
            actionContext: .editor,
            doubleTapAccessibilityLabel: LocalizedStringResource("Toggle Player Visibility", bundle: .module)
        )
    }
    .onAppear {
        model.isExpandedId = MapModel.previewId
    }
}
