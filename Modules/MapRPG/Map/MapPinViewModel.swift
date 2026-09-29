// @copyright André Trettin

import CoreRPG
import SwiftUI

// Split out of MapPinView.swift — this file holds the @Observable model
// layer, MapPinView.swift keeps the pure View. See CODE_AUDIT §9.13.

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

    /// Duplicates a pin next to the original and returns the duplicate's id.
    @discardableResult
    func copyPin(id: UUID) -> UUID? {
        guard let sourceIndex = mapPinNodes.firstIndex(where: { $0.id == id }) else { return nil }
        var pin = mapPinNodes[sourceIndex].pin
        pin.id = UUID()
        pin.location = pin.location + (pin.size.size.width + 25)
        let node = MapPinNode(pin: pin)
        node.attach(to: self)
        mapPinNodes.insert(node, at: sourceIndex)
        rebuildLayerNodes()
        return node.id
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
        }
        // A master's tap either joins battle prep or opens the pin action
        // menu — decided by `MapEditorActionRouter.handlePinSingleTap`,
        // which toggles `isExpandedId` itself (via `handleLongPress`) once
        // it knows battle prep didn't consume the tap. Nothing to do here
        // for `.gameMaster` up front.
        interactionHandler?(.tap(pin: node.pin, isPointer: node.isPointer))
    }

    /// Toggles the pin action menu. Despite the name, this is no longer tied
    /// to a physical long-press gesture — it's invoked from a master's
    /// single tap (via `MapEditorActionRouter`) once battle prep doesn't
    /// consume the tap, and directly from VoiceOver's "Open Pin Actions"
    /// custom action.
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
        updatedPin.timeInterval = GameController.bumpedTimeInterval(from: updatedPin.timeInterval)
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
            // Select the duplicate, so the action menu moves on to it.
            if let copyId = copyPin(id: node.id) {
                setExpanded(id: copyId)
            }
        case (.editor, .photo):
            node.isPhotoSelectionPresented = true
            return
        case (.editor, .resize):
            resizePin(id: node.id)
        case (.editor, .dead):
            toggleDeadPin(id: node.id)
        case (.editor, .visibility), (.editor, .zoom), (.editor, .highlight), (.editor, .battle),
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
