// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

// The @Observable model layer (MapPinInteractionEvent, MapPinNode,
// MapPinViewModel) moved to MapPinViewModel.swift — this file keeps the pure
// View. See CODE_AUDIT §9.13.

struct MapPinView: View {
    let model: MapPinNode
    let pinSize: CGSize
    let canMove: Bool
    let actionContext: MapPinActionContext
    let doubleTapAccessibilityLabel: LocalizedStringResource

    var body: some View {
        MapPinContentView(
            model: model,
            pinSize: pinSize,
            canMove: canMove,
            actionContext: actionContext,
            doubleTapAccessibilityLabel: doubleTapAccessibilityLabel
        )
    }
}

/// What a pin accepts by drop in the editor: a photo for its image or a character.
/// The dropped `module` tells them apart.
public struct MapPinDropTransferable: LinkDataTransferable {
    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .photoLink)
        CodableRepresentation(contentType: .characterLink)
    }
}

private struct MapPinTapGestureModifier: ViewModifier {
    let model: MapPinNode
    let actionContext: MapPinActionContext
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        switch actionContext {
        case .none:
            // Player/viewer taps have separate model actions, so preserve exact
            // single-versus-double semantics even though single tap waits.
            content.highPriorityGesture(
                doubleTapGesture.exclusively(before: singleTapGesture)
            )
        case .editor:
            // Editor action menus toggle immediately. The simultaneous
            // double-tap action still closes an open menu before emitting its
            // domain action.
            content
                .highPriorityGesture(singleTapGesture)
                .simultaneousGesture(doubleTapGesture)
        case .gameMaster:
            // A master's tap either joins battle prep or opens the pin
            // action menu — see `MapEditorActionRouter.handlePinSingleTap`.
            // Long press is no longer used for pins.
            content.highPriorityGesture(
                doubleTapGesture.exclusively(before: singleTapGesture)
            )
        }
    }

    private var singleTapGesture: some Gesture {
        TapGesture().onEnded {
            withAnimation(reduceMotion ? nil : .default) {
                model.handleTap(context: actionContext)
            }
        }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            withAnimation(reduceMotion ? nil : .default) {
                model.handleDoubleTap()
            }
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` property on `MapPinView` itself.

private struct MapPinContentView: View {
    let model: MapPinNode
    let pinSize: CGSize
    let canMove: Bool
    let actionContext: MapPinActionContext
    let doubleTapAccessibilityLabel: LocalizedStringResource

    /// VoiceOver's "Move Left/Right/Up/Down" custom actions step by this many points.
    private static let accessibilityMoveStep: CGFloat = 10
    /// Inset ratio for the dead-pin "X" mark relative to the smaller pin dimension.
    private static let deadMarkInsetRatio: CGFloat = 0.24

    @Environment(MapRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pin: MapPinModel { model.presentedPin }

    private var isActiveBattleAttacker: Bool {
        let battleRound = root.mapGameControllable.battleRoundModel
        return battleRound.isRunning && battleRound.activePinId == pin.id
    }

    var body: some View {
        root.photoRoot.viewController.mapImage(
            root: root.photoRoot,
            for: pin.photoId,
            size: pinSize,
            color: pin.color
        )
        // The source photo is rarely square, so the resizable `.fill` image
        // overflows the pin's circular frame in one axis. Anchor that overflow
        // to the top so a portrait character keeps their head in view instead
        // of centering on the torso.
        .frame(width: pinSize.width, height: pinSize.height, alignment: .top)
        .overlay {
            if !pin.isShown {
                Circle()
                    .fill(.green.opacity(0.5))
                    .accessibilityHidden(true)
            }
        }
        .clipShape(.circle)
        .background {
            // Apply after clipping so the selection halo can extend beyond
            // the pin while the image itself remains circular.
            MapSelectionHalo(
                contentDiameter: max(pinSize.width, pinSize.height),
                isVisible: model.isExpanded
            )
        }
        .overlay {
            MapPinHealthRing(pinId: pin.id, broadcastHealthPercent: pin.healthPercent, isDead: pin.isDead)
        }
        .overlay {
            if actionContext == .editor, pin.characterId == nil {
                Circle()
                    .strokeBorder(.red, lineWidth: 3)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            if pin.isDead {
                Image(systemName: "xmark")
                    .resizable()
                    .scaledToFit()
                    .padding(min(pinSize.width, pinSize.height) * Self.deadMarkInsetRatio)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 1, x: 1, y: 1)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            Circle()
                .stroke(isActiveBattleAttacker ? .blue : .red, lineWidth: 4)
                .padding(-4)
                .opacity(pin.isHighlighted || isActiveBattleAttacker ? 1 : 0)
                .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : .easeInOut, value: isActiveBattleAttacker)
        .shadow(color: .black, radius: 4, x: 4, y: 4)
#if os(visionOS)
        .hoverEffect(.highlight)
        .hoverEffect { effect, isActive, _ in
            effect.scaleEffect(isActive ? 1.2 : 1)
        }
#endif
        .modifier(MapPinTapGestureModifier(
            model: model,
            actionContext: actionContext,
            reduceMotion: reduceMotion
        ))
#if os(macOS) || os(visionOS)
        // One destination for both link types: stacked `dropDestination`s for different
        // types on the same view don't all receive their drops.
        .dropDestination(
            for: MapPinDropTransferable.self,
            isEnabled: actionContext == .editor
        ) { links, _ in
            // A pin owns one displayed photo and one character. Accept only the first
            // dropped item so one user drop produces one model/persistence event.
            guard let link = links.first else { return }
            switch link.module {
            case .photo: model.replacePhoto(with: link.itemId)
            case .value where link.entryId == nil: model.replaceCharacter(with: link.itemId)
            default: break
            }
        }
#endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pinAccessibilityLabel)
        .accessibilityValue(pinAccessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            handleTap()
        }
        .accessibilityAction(named: Text("Open Pin Actions", bundle: .module)) {
            guard actionContext == .gameMaster else { return }
            withAnimation(reduceMotion ? nil : .default) {
                model.handleLongPress(context: actionContext)
            }
        }
        .accessibilityAction(named: Text(doubleTapAccessibilityLabel)) {
            withAnimation(reduceMotion ? nil : .default) {
                model.handleDoubleTap()
            }
        }
#if !os(tvOS)
        .accessibilityAction(named: Text("Move Left", bundle: .module)) {
            movePinBy(x: -Self.accessibilityMoveStep, y: 0)
        }
        .accessibilityAction(named: Text("Move Right", bundle: .module)) {
            movePinBy(x: Self.accessibilityMoveStep, y: 0)
        }
        .accessibilityAction(named: Text("Move Up", bundle: .module)) {
            movePinBy(x: 0, y: -Self.accessibilityMoveStep)
        }
        .accessibilityAction(named: Text("Move Down", bundle: .module)) {
            movePinBy(x: 0, y: Self.accessibilityMoveStep)
        }
#endif
    }

#if !os(tvOS)
    private func movePinBy(x: CGFloat, y: CGFloat) {
        guard canMove else { return }
        model.move(by: CGSize(width: x, height: y))
    }
#endif

    private var pinAccessibilityLabel: Text {
        guard !pin.name.isEmpty else {
            return Text("Map Pin", bundle: .module)
        }
        return Text(verbatim: pin.name)
    }

    private var pinAccessibilityValue: Text {
        // The ring color (blue = active battle attacker, red = highlighted) is
        // otherwise the only signal for this state — announce it too, mirroring
        // the pattern already used for shown/dead/highlighted below.
        var value = Text(pinAccessibilityValueResource)
        // The ring color is also the only signal for the remaining hit points: announce the
        // broadcast percent too. See CODE_AUDIT_20 §8.1.
        if let healthPercent = pin.healthPercent {
            value = Text("\(value), \(Text("Health: \(Int(healthPercent.rounded())) percent", bundle: .module))")
        }
        guard isActiveBattleAttacker else { return value }
        return Text("\(value), \(Text("Active Battle Attacker", bundle: .module))")
    }

    private var pinAccessibilityValueResource: LocalizedStringResource {
        switch (pin.isShown, pin.isDead, pin.isHighlighted) {
        case (true, false, false): LocalizedStringResource("Visible to Players, Alive, Not Highlighted", bundle: .module)
        case (true, false, true): LocalizedStringResource("Visible to Players, Alive, Highlighted", bundle: .module)
        case (true, true, false): LocalizedStringResource("Visible to Players, Dead, Not Highlighted", bundle: .module)
        case (true, true, true): LocalizedStringResource("Visible to Players, Dead, Highlighted", bundle: .module)
        case (false, false, false): LocalizedStringResource("Hidden from Players, Alive, Not Highlighted", bundle: .module)
        case (false, false, true): LocalizedStringResource("Hidden from Players, Alive, Highlighted", bundle: .module)
        case (false, true, false): LocalizedStringResource("Hidden from Players, Dead, Not Highlighted", bundle: .module)
        case (false, true, true): LocalizedStringResource("Hidden from Players, Dead, Highlighted", bundle: .module)
        }
    }

    private func handleTap() {
        withAnimation(reduceMotion ? nil : .default) {
            model.handleTap(context: actionContext)
        }
    }
}

/// The pin's ring: it doubles as a health bar once a hit-points entry is linked — red, orange
/// or green by remaining percent, grey while unknown. A dead pin's black ring always takes
/// precedence. Its own view, so the formula behind the live percent is resolved only when its
/// inputs or the linked values change, not on every render of the pin during drag and zoom.
/// See CODE_AUDIT_20 §7.1, §8.1.
private struct MapPinHealthRing: View {
    let pinId: UUID
    let broadcastHealthPercent: Double?
    let isDead: Bool

    @Environment(MapRootModel.self) private var root
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    /// Prefers a live read of the linked hit-points entry over the pin's
    /// broadcast `healthPercent` whenever this pin is a tracked combatant —
    /// only true on the game master's own screen (see
    /// `GameController.healthPercent(for:)`) — so the border reacts the
    /// instant the entry changes instead of waiting for the next push. A
    /// player has no local combatant for this pin and falls through to the
    /// last broadcast value.
    private var healthPercent: Double? {
        guard let combatant = root.mapGameControllable.battleRoundModel.combatant(pinId: pinId) else {
            return broadcastHealthPercent
        }
        return root.mapGameControllable.healthPercent(for: combatant)
    }

    var body: some View {
        let healthPercent = healthPercent
        // Without color, the ring pattern carries the health band: solid, dashed, dotted.
        let dash: [CGFloat] = isDead || !differentiateWithoutColor ? [] : MapPinModel.healthRingDash(for: healthPercent)
        Circle()
            .strokeBorder(
                isDead ? .black : MapPinModel.healthBorderColor(for: healthPercent),
                style: StrokeStyle(lineWidth: isDead ? 5 : 2, dash: dash)
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    @Previewable var model: MapPinViewModel = MapPinViewModel(mapPins: [MapPinModel.empty(MapModel.previewId), MapPinModel.empty(UUID())], pointer: .empty(UUID()))

    MapPinView(
        model: model.mapPinNodes[0],
        pinSize: model.mapPins[0].size == .normal ? CGSize(width: 64, height: 64) : CGSize(width: 128, height: 128),
        canMove: true,
        actionContext: .editor,
        doubleTapAccessibilityLabel: LocalizedStringResource("Toggle Player Visibility", bundle: .module)
    )
    .onChange(of: model.isExpandedId) {
        withAnimation {
            var pin = model.mapPins[0]
            pin.size = pin.size == .normal ? .large : .normal
            model.setPinPointer(updatedPin: pin)
        }
    }
    .offset(x: model.mapPins[0].location.x, y: model.mapPins[0].location.y)
    .environment(MapRootModel.preview)
}
