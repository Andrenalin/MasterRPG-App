// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreGraphics
import Foundation
import MapRPG
import RealityKit

/// The popovers the table shows over a pin or a point of the map.
enum TablePopoverKind: CaseIterable, Hashable, Sendable {
    /// The game master's pin action menu.
    case pinMenu
    /// A pin's photo.
    case pinPhoto
    /// The photo the game master shows on the map.
    case mapPhoto

    /// The attachment's id in the visionOS volume.
    var attachmentId: String {
        switch self {
        case .pinMenu: "pin-menu"
        case .pinPhoto: "pin-photo"
        case .mapPhoto: "map-photo"
        }
    }

    fileprivate var anchorName: String {
        switch self {
        case .pinMenu: "PinMenuAnchor"
        case .pinPhoto: "PinPhotoAnchor"
        case .mapPhoto: "MapPhotoAnchor"
        }
    }
}

/// One anchor per popover kind: where it stands as a RealityKit attachment, on visionOS.
@MainActor
struct TablePopoverAnchors {
    private let pinMenu = TablePopoverAnchor(name: TablePopoverKind.pinMenu.anchorName)
    private let pinPhoto = TablePopoverAnchor(name: TablePopoverKind.pinPhoto.anchorName)
    private let mapPhoto = TablePopoverAnchor(name: TablePopoverKind.mapPhoto.anchorName)

    subscript(kind: TablePopoverKind) -> TablePopoverAnchor {
        switch kind {
        case .pinMenu: pinMenu
        case .pinPhoto: pinPhoto
        case .mapPhoto: mapPhoto
        }
    }
}

extension GameTableModel {
    // MARK: - Popover attachments (visionOS)

    /// Registers the SwiftUI attachment used for a popover. See `TablePopoverAnchor` for how it
    /// stands on the table and why a stale attachment is discarded first.
    func registerAttachment(_ attachment: Entity, for kind: TablePopoverKind) {
        popoverAnchors[kind].register(attachment, in: renderer.root)
        updateAttachmentPosition(for: kind)
    }

    /// The attachment view reports its own height, in meters, whenever its layout changes.
    func attachmentHeightChanged(_ height: Float, for kind: TablePopoverKind) {
        popoverAnchors[kind].attachmentHeightChanged(height)
    }

    /// Detaches every popover attachment from the persisted table root before its owning
    /// `RealityView`/window tears down. See `TablePopoverAnchor.detach()`.
    func detachAttachments() {
        for kind in TablePopoverKind.allCases {
            popoverAnchors[kind].detach()
        }
    }

    func updateAttachmentPositions() {
        for kind in TablePopoverKind.allCases {
            updateAttachmentPosition(for: kind)
        }
    }

    /// Stands the popover's anchor on its target, or hides it when it has none.
    func updateAttachmentPosition(for kind: TablePopoverKind, cachedPawn: PinPawn? = nil) {
        guard let position = popoverAnchorPosition(for: kind, cachedPawn: cachedPawn) else {
            popoverAnchors[kind].hide()
            return
        }
        popoverAnchors[kind].show(at: SIMD3<Float>(
            position.x,
            position.y + Self.pinMenuArrowTipHeight,
            position.z
        ))
    }

    /// How far above a pin's base the popover's arrow ends: just clear of the token's top.
    static let pinMenuArrowTipHeight: Float = 0.03

    /// The pin a popover of `kind` is open on, `nil` for one that is not open or belongs to no
    /// pin.
    func popoverPinId(for kind: TablePopoverKind) -> UUID? {
        switch kind {
        case .pinMenu:
            selectedPin != nil && isGameMaster ? selectedPinId : nil
        case .pinPhoto:
            photoPin != nil ? photoPinId : nil
        case .mapPhoto:
            nil
        }
    }

    private func popoverAnchorPosition(for kind: TablePopoverKind, cachedPawn: PinPawn?) -> SIMD3<Float>? {
        if kind == .mapPhoto { return mapPhotoPosition }
        guard let pinId = popoverPinId(for: kind),
              let pawn = cachedPawn ?? setup.pinPawns.first(where: { $0.pinId == pinId }) else { return nil }
        return pawn.entity.position
    }

#if !os(visionOS)
    // MARK: - Popover sources (camera-based table)

    /// Projects every open popover's target into the table view. Runs every rendered frame;
    /// `project` maps a scene position to the table view's coordinate space.
    func updatePopoverSources(project: (SIMD3<Float>) -> CGPoint?) {
        for kind in TablePopoverKind.allCases {
            setPopoverSource(popoverSource(for: kind, project: project), for: kind)
        }
    }

    private func popoverSource(for kind: TablePopoverKind, project: (SIMD3<Float>) -> CGPoint?) -> TablePopoverSource? {
        if kind == .mapPhoto {
            guard let photo = mapPhoto,
                  let position = mapPhotoPosition,
                  let point = project(setup.pinContainer.convert(position: position, to: nil)),
                  let frame = MapPhotoPopoverSource.rectangle(atViewportPoint: point)
            else { return nil }
            return TablePopoverSource(id: photo.itemId, frame: frame)
        }
        guard let pinId = popoverPinId(for: kind),
              let pawn = setup.pinPawns.first(where: { $0.pinId == pinId }) else { return nil }
        let bounds = pawn.entity.visualBounds(relativeTo: nil)
        let corners = TablePopoverSource.corners(min: bounds.min, max: bounds.max)
        return TablePopoverSource.frame(enclosing: corners.map(project)).map {
            TablePopoverSource(id: pinId, frame: $0)
        }
    }

    /// Publishes only a visible change: the source is recomputed every rendered frame.
    private func setPopoverSource(_ source: TablePopoverSource?, for kind: TablePopoverKind) {
        guard let source else {
            clearPopoverSource(for: kind)
            return
        }
        if source.differsVisibly(from: popoverSources[kind]) {
            popoverSources[kind] = source
        }
    }

    func clearPopoverSource(for kind: TablePopoverKind) {
        if popoverSources[kind] != nil {
            popoverSources[kind] = nil
        }
    }
#endif
}
#endif
