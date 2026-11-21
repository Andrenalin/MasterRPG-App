// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import RealityKit

/// The three control groups a seat's dock opens, one at a time like radio buttons.
enum TableSeatGroup: CaseIterable, Hashable, Sendable {
    /// Quit, the connection, the players and the audio.
    case controls
    /// The windows of the game, map, photo, audio, weather and 3D modules.
    case windowsOne
    /// The windows of the table, pdf, character, adventure, dice and rule modules.
    case windowsTwo

    var panel: TableSeatPanel {
        switch self {
        case .controls: .controls
        case .windowsOne: .windowsOne
        case .windowsTwo: .windowsTwo
        }
    }
}

/// The control panels a seat has on the table (visionOS), as RealityKit attachments.
enum TableSeatPanel: CaseIterable, Hashable, Sendable {
    /// The three buttons that open the groups, at the map's start. Always there.
    case dock
    /// The panels of the groups, which open above the dock, one at a time.
    case controls, windowsOne, windowsTwo
    /// The game master's button that opens the map controls, at the map's end.
    case mapDock
    /// The map controls, which open above the map dock.
    case map

    var attachmentId: String {
        switch self {
        case .dock: "seat-panel-dock"
        case .controls: "seat-panel-controls"
        case .windowsOne: "seat-panel-windows-one"
        case .windowsTwo: "seat-panel-windows-two"
        case .mapDock: "seat-panel-map-dock"
        case .map: "seat-panel-map"
        }
    }

    /// The end of the map the panel stands at: the dock at its start, the map dock at its end.
    var side: TableSeatControlsLayout.Side {
        switch self {
        case .dock, .controls, .windowsOne, .windowsTwo: .leading
        case .mapDock, .map: .trailing
        }
    }

    /// The panel this one opens above, up the slope.
    var opensAbove: TableSeatPanel? {
        switch self {
        case .controls, .windowsOne, .windowsTwo: .dock
        case .map: .mapDock
        case .dock, .mapDock: nil
        }
    }

    fileprivate var anchorName: String {
        switch self {
        case .dock: "SeatPanelDockAnchor"
        case .controls: "SeatPanelControlsAnchor"
        case .windowsOne: "SeatPanelWindowsOneAnchor"
        case .windowsTwo: "SeatPanelWindowsTwoAnchor"
        case .mapDock: "SeatPanelMapDockAnchor"
        case .map: "SeatPanelMapAnchor"
        }
    }
}

/// Stands a SwiftUI control panel on the table beside a seat's dice, sloped toward the seated
/// player. Unlike `TablePopoverAnchor` it does not billboard: a seated player's panel stays where
/// it is. It lives under the table root, so its position follows the table, but its scale is set
/// from the outside (`setScale(_:)`) to cancel the table's own, which keeps the buttons the same
/// size when the table is pinched smaller.
///
/// The entity's origin is the panel's bottom-centre; the attachment hangs above it, raised by half
/// its own height.
@MainActor
final class TableSeatPanelAnchor {
    let entity: Entity
    private(set) var attachment: Entity?
    /// The attachment's size in meters at its own scale, as it reports it.
    private(set) var size = SIMD2<Float>(0, 0)

    init(name: String) {
        entity = Entity()
        entity.name = name
    }

    /// Adopts the attachment of the current `RealityView` mount; see
    /// `TablePopoverAnchor.register(_:in:)` for why a stale one is discarded first.
    func register(_ attachment: Entity, in root: Entity) {
        if let previous = self.attachment, previous !== attachment {
            previous.removeFromParent()
        }
        self.attachment = attachment
        if entity.parent == nil {
            root.addChild(entity)
        }
        if attachment.parent !== entity {
            entity.addChild(attachment)
        }
        attachment.position = SIMD3<Float>(0, size.y / 2, 0)
    }

    /// Detaches the attachment before its `RealityView` tears down; see
    /// `TablePopoverAnchor.detach()`.
    func detach() {
        attachment?.removeFromParent()
        attachment = nil
    }

    /// The attachment view reports its size, in meters, whenever its layout changes.
    /// - Returns: whether the size changed.
    @discardableResult
    func sizeChanged(_ newSize: SIMD2<Float>) -> Bool {
        guard newSize.x.isFinite, newSize.y.isFinite, newSize.x >= 0, newSize.y >= 0, newSize != size else { return false }
        size = newSize
        attachment?.position = SIMD3<Float>(0, newSize.y / 2, 0)
        return true
    }

    func place(_ placement: TableSeatControlsLayout.Placement) {
        entity.position = placement.position
        entity.orientation = placement.orientation
    }

    func setScale(_ scale: Float) {
        entity.scale = SIMD3<Float>(repeating: scale)
    }

    func setEnabled(_ isEnabled: Bool) {
        attachment?.isEnabled = isEnabled
    }
}

/// One anchor per panel.
@MainActor
struct TableSeatPanelAnchors {
    private let anchors = Dictionary(uniqueKeysWithValues: TableSeatPanel.allCases.map {
        ($0, TableSeatPanelAnchor(name: $0.anchorName))
    })

    subscript(panel: TableSeatPanel) -> TableSeatPanelAnchor {
        guard let anchor = anchors[panel] else { preconditionFailure("No anchor for \(panel)") }
        return anchor
    }
}
#endif
