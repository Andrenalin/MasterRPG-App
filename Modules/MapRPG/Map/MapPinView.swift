// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

/// A single event channel keeps controller/network side effects out of every pin
/// view. The store is configured once by the owning map surface.
enum MapPinInteractionEvent: Equatable {
    case tap(pin: MapPinModel, isPointer: Bool)
    case longPress(pin: MapPinModel, isPointer: Bool)
    case doubleTap(pin: MapPinModel, isPointer: Bool)
    case beginMove(pin: MapPinModel, isPointer: Bool)
    case move(pin: MapPinModel, isPointer: Bool)
    case action(
        MapPinButtonType,
        pin: MapPinModel,
        isPointer: Bool,
        context: MapPinActionContext
    )
}

@MainActor @Observable
final class MapPinNode: Identifiable {
    init(pin: MapPinModel, isPointer: Bool = false) {
        self.id = pin.id
        self.pin = pin
        self.isPointer = isPointer
    }

    let id: UUID
    private(set) var pin: MapPinModel
    private(set) var isExpanded = false
    var isPhotoSelectionPresented = false
    let isPointer: Bool

    @ObservationIgnored private weak var store: MapPinViewModel?

    var presentedPin: MapPinModel {
        guard isPointer else { return pin }
        var presented = pin
        presented.isDead = false
        presented.isHighlighted = false
        return presented
    }

    func handleTap(context: MapPinActionContext) {
        store?.handleTap(on: self, context: context)
    }

    func handleDoubleTap() {
        store?.handleDoubleTap(on: self)
    }

    func handleLongPress(context: MapPinActionContext) {
        store?.handleLongPress(on: self, context: context)
    }

    func move(by translation: CGSize) {
        store?.move(self, by: translation)
    }

    func beginMove() {
        store?.beginMove(self)
    }

    func perform(_ action: MapPinButtonType, context: MapPinActionContext) {
        store?.perform(action, on: self, context: context)
    }

    func replacePhoto(with itemId: UUID?) {
        store?.replacePhoto(pinId: id, itemId: itemId)
    }

    fileprivate func attach(to store: MapPinViewModel) {
        self.store = store
    }

    fileprivate func update(pin: MapPinModel) {
        guard self.pin != pin else { return }
        self.pin = pin
    }

    fileprivate func setExpanded(_ isExpanded: Bool) {
        guard self.isExpanded != isExpanded else { return }
        self.isExpanded = isExpanded
        if !isExpanded {
            isPhotoSelectionPresented = false
        }
    }
}

@MainActor @Observable
final class MapPinViewModel {
    typealias InteractionHandler = @MainActor (MapPinInteractionEvent) -> Void

    init(mapPins: [MapPinModel], pointer: MapPinModel) {
        let nodes = mapPins.map { MapPinNode(pin: $0) }
        mapPinNodes = nodes
        ordinaryPinNodes = nodes.filter { !$0.pin.isZoom }
        zoomedPinNodes = nodes.filter { $0.pin.isZoom }
        pointerNode = MapPinNode(pin: pointer, isPointer: true)
        attachNodes()
    }

    /// Structural changes invalidate the layer. Mutating one node does not
    /// replace this array, so sibling pins retain identity and stay untouched.
    private(set) var mapPinNodes: [MapPinNode]
    /// Layer membership is rebuilt only for structural or zoom-state changes.
    /// A drag can therefore update one node without making the parent layer
    /// observe and filter every sibling pin.
    private(set) var ordinaryPinNodes: [MapPinNode]
    private(set) var zoomedPinNodes: [MapPinNode]
    private(set) var pointerNode: MapPinNode
    private var expandedId: UUID?

    @ObservationIgnored private var interactionHandler: InteractionHandler?

    /// Compatibility DTO surface for controllers and persistence. Rendering
    /// should iterate `mapPinNodes` and pass each node directly to the leaf.
    var mapPins: [MapPinModel] {
        get { mapPinNodes.map(\.pin) }
        set { reconcileMapPins(with: newValue) }
    }

    var pointer: MapPinModel {
        get { pointerNode.pin }
        set { reconcilePointer(with: newValue) }
    }

    var isExpandedId: UUID? {
        get { expandedId }
        set { setExpanded(id: newValue) }
    }

    func configureInteractionHandler(_ handler: InteractionHandler?) {
        interactionHandler = handler
    }

    func pinNode(for id: UUID) -> MapPinNode? {
        if pointerNode.id == id { return pointerNode }
        return mapPinNodes.first { $0.id == id }
    }

    func pinPointer(for id: UUID) -> MapPinModel? {
        pinNode(for: id)?.pin
    }

    func setPinPointer(updatedPin: MapPinModel) {
        if pointerNode.id == updatedPin.id {
            pointerNode.update(pin: updatedPin)
        } else if let node = pinNode(for: updatedPin.id) {
            let layerChanged = node.pin.isZoom != updatedPin.isZoom
            node.update(pin: updatedPin)
            if layerChanged {
                rebuildLayerNodes()
            }
        }
    }

    func removePin(id: UUID) {
        guard let index = mapPinNodes.firstIndex(where: { $0.id == id }) else { return }
        mapPinNodes.remove(at: index)
        rebuildLayerNodes()
        if expandedId == id { setExpanded(id: nil) }
    }

    func replacePhoto(pinId: UUID, itemId: UUID?) {
        guard let node = pinNode(for: pinId) else { return }
        var updatedPin = node.pin
        guard updatedPin.photoId != itemId else { return }
        updatedPin.photoId = itemId
        node.update(pin: updatedPin)
        interactionHandler?(.action(
            .photo,
            pin: updatedPin,
            isPointer: node.isPointer,
            context: .editor
        ))
    }

    func copyPin(id: UUID) {
        guard let sourceIndex = mapPinNodes.firstIndex(where: { $0.id == id }) else { return }
        var pin = mapPinNodes[sourceIndex].pin
        pin.id = UUID()
        pin.location = pin.location + (pin.size.size.width + 25)
        let node = MapPinNode(pin: pin)
        node.attach(to: self)
        mapPinNodes.insert(node, at: sourceIndex)
        rebuildLayerNodes()
    }

    func resizePin(id: UUID) {
        guard let node = pinNode(for: id) else { return }
        var updatedPin = node.pin
        updatedPin.size = updatedPin.size.nextSize()
        node.update(pin: updatedPin)
    }

    func toggleDeadPin(id: UUID) {
        guard let node = pinNode(for: id) else { return }
        var updatedPin = node.pin
        updatedPin.isDead.toggle()
        node.update(pin: updatedPin)
    }

    fileprivate func handleTap(on node: MapPinNode, context: MapPinActionContext) {
        if context == .editor {
            setExpanded(id: node.isExpanded ? nil : node.id)
        } else if context == .gameMaster {
            setExpanded(id: nil)
        }
        interactionHandler?(.tap(pin: node.pin, isPointer: node.isPointer))
    }

    fileprivate func handleLongPress(
        on node: MapPinNode,
        context: MapPinActionContext
    ) {
        guard context == .gameMaster, !node.isPointer else { return }
        setExpanded(id: node.isExpanded ? nil : node.id)
        interactionHandler?(.longPress(pin: node.pin, isPointer: false))
    }

    fileprivate func handleDoubleTap(on node: MapPinNode) {
        setExpanded(id: nil)
        interactionHandler?(.doubleTap(pin: node.pin, isPointer: node.isPointer))
    }

    fileprivate func move(_ node: MapPinNode, by translation: CGSize) {
        guard translation != .zero else { return }
        var updatedPin = node.pin
        updatedPin.location = CGPoint(
            x: updatedPin.location.x + translation.width,
            y: updatedPin.location.y + translation.height
        )
        updatedPin.timeInterval = max(
            Date.now.timeIntervalSince1970,
            updatedPin.timeInterval.nextUp
        )
        node.update(pin: updatedPin)
        interactionHandler?(.move(pin: updatedPin, isPointer: node.isPointer))
    }

    fileprivate func beginMove(_ node: MapPinNode) {
        collapseActions(for: node)
        interactionHandler?(.beginMove(pin: node.pin, isPointer: node.isPointer))
    }

    fileprivate func collapseActions(for node: MapPinNode) {
        guard expandedId == node.id else { return }
        setExpanded(id: nil)
    }

    fileprivate func perform(
        _ action: MapPinButtonType,
        on node: MapPinNode,
        context: MapPinActionContext
    ) {
        let originalPin = node.pin
        switch (context, action) {
        case (.editor, .remove):
            removePin(id: node.id)
        case (.editor, .copy):
            copyPin(id: node.id)
        case (.editor, .photo):
            node.isPhotoSelectionPresented = true
            return
        case (.editor, .resize):
            resizePin(id: node.id)
        case (.editor, .dead):
            toggleDeadPin(id: node.id)
        case (.editor, .visibility), (.editor, .zoom), (.editor, .battle),
             (.gameMaster, _), (.none, _):
            break
        }

        let eventPin = pinNode(for: node.id)?.pin ?? originalPin
        interactionHandler?(.action(
            action,
            pin: eventPin,
            isPointer: node.isPointer,
            context: context
        ))
    }

    private func setExpanded(id: UUID?) {
        guard expandedId != id else { return }
        if let expandedId {
            pinNode(for: expandedId)?.setExpanded(false)
        }
        expandedId = id
        if let id {
            pinNode(for: id)?.setExpanded(true)
        }
    }

    private func reconcileMapPins(with pins: [MapPinModel]) {
        var existingNodes: [UUID: MapPinNode] = [:]
        for node in mapPinNodes where existingNodes[node.id] == nil {
            existingNodes[node.id] = node
        }

        var layerMembershipChanged = false
        let reconciled = pins.map { pin in
            if let node = existingNodes.removeValue(forKey: pin.id) {
                layerMembershipChanged = layerMembershipChanged || node.pin.isZoom != pin.isZoom
                node.update(pin: pin)
                return node
            }
            let node = MapPinNode(pin: pin)
            node.attach(to: self)
            return node
        }

        let hasStructuralChange = reconciled.count != mapPinNodes.count
            || zip(reconciled, mapPinNodes).contains { $0.id != $1.id }
        if hasStructuralChange {
            mapPinNodes = reconciled
        }
        if hasStructuralChange || layerMembershipChanged {
            rebuildLayerNodes()
        }
        if let expandedId, !pins.contains(where: { $0.id == expandedId }) {
            setExpanded(id: nil)
        }
    }

    private func reconcilePointer(with pin: MapPinModel) {
        if pointerNode.id == pin.id {
            pointerNode.update(pin: pin)
        } else {
            pointerNode = MapPinNode(pin: pin, isPointer: true)
            pointerNode.attach(to: self)
        }
    }

    private func attachNodes() {
        mapPinNodes.forEach { $0.attach(to: self) }
        pointerNode.attach(to: self)
    }

    private func rebuildLayerNodes() {
        let ordinary = mapPinNodes.filter { !$0.pin.isZoom }
        let zoomed = mapPinNodes.filter { $0.pin.isZoom }
        if ordinary.map(\.id) != ordinaryPinNodes.map(\.id) {
            ordinaryPinNodes = ordinary
        }
        if zoomed.map(\.id) != zoomedPinNodes.map(\.id) {
            zoomedPinNodes = zoomed
        }
    }
}

struct MapPinView: View {
    let model: MapPinNode
    let pinSize: CGSize
    let canMove: Bool
    let actionContext: MapPinActionContext
    let doubleTapAccessibilityLabel: LocalizedStringResource

    @Environment(MapRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pin: MapPinModel { model.presentedPin }

    private var isActiveBattleAttacker: Bool {
        let battleRound = root.mapGameControllable.battleRoundModel
        return battleRound.isRunning && battleRound.activePinId == pin.id
    }

    var body: some View {
        pinView
    }

    private var pinView: some View {
        root.photoRoot.viewController.mapImage(
            root: root.photoRoot,
            for: pin.photoId,
            size: pinSize,
            color: pin.color
        )
        .frame(width: pinSize.width, height: pinSize.height)
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
            Circle()
                .strokeBorder(pin.isDead ? .black : .gray, lineWidth: pin.isDead ? 5 : 2)
                .accessibilityHidden(true)
        }
        .overlay {
            if pin.isDead {
                Image(systemName: "xmark")
                    .resizable()
                    .scaledToFit()
                    .padding(min(pinSize.width, pinSize.height) * 0.24)
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
        .dropDestination(
            for: LinkPhotoData.self,
            isEnabled: actionContext == .editor
        ) { photos, _ in
            guard let photo = photos.first else { return }
            // A pin owns one displayed photo. Accept only the first dropped
            // item so one user drop produces one model/persistence event.
            model.replacePhoto(with: photo.itemId)
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
            movePinBy(x: -10, y: 0)
        }
        .accessibilityAction(named: Text("Move Right", bundle: .module)) {
            movePinBy(x: 10, y: 0)
        }
        .accessibilityAction(named: Text("Move Up", bundle: .module)) {
            movePinBy(x: 0, y: -10)
        }
        .accessibilityAction(named: Text("Move Down", bundle: .module)) {
            movePinBy(x: 0, y: 10)
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
        Text(pinAccessibilityValueResource)
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
            // A master uses the same single-tap highlight behavior as a player.
            // The action fan is deliberately behind a stationary long press so
            // tapping and dragging never accidentally expose its hit targets.
#if os(tvOS)
            content.highPriorityGesture(
                doubleTapGesture.exclusively(before: singleTapGesture)
            )
#else
            content.highPriorityGesture(
                longPressGesture.exclusively(
                    before: doubleTapGesture.exclusively(before: singleTapGesture)
                )
            )
#endif
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

#if !os(tvOS)
    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45, maximumDistance: 3)
            .onEnded { succeeded in
                guard succeeded else { return }
                withAnimation(reduceMotion ? nil : .default) {
                    model.handleLongPress(context: actionContext)
                }
            }
    }
#endif
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
