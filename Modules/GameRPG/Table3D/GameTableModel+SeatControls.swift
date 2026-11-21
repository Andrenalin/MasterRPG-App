// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import RealityKit
#if os(visionOS)
import Spatial
import TabletopKit
#endif

extension GameTableModel {
    /// How many dice a seat's row can have a remove popover for. A set with more dice than
    /// that is not removable from the table beyond its first dice; the editor of the 2D window
    /// still is.
    static let maxRemovePopovers = 24

    /// Opens a control group's panel above the dock, closing the one that was open; the open
    /// group's own button closes it.
    func toggleSeatGroup(_ group: TableSeatGroup) {
        openSeatGroup = openSeatGroup == group ? nil : group
    }

    func toggleMapControls() {
        isMapControlsOpen.toggle()
    }

    /// Opens the map controls the first time a map is shown, so the game master finds them; they
    /// stay as the game master leaves them from then on.
    func openMapControlsOnFirstMap() {
        guard !didOpenMapControlsForMap, isGameMaster, currentMapId != nil else { return }
        didOpenMapControlsForMap = true
        isMapControlsOpen = true
    }

    /// Brings the seat's panels in step with the map they start and end at.
    func refreshSeatPanelPositions() {
        openMapControlsOnFirstMap()
#if os(visionOS)
        updateSeatPanelPositions()
#endif
    }

    /// Tells the seat what its dice row holds: the set index of every die on the table, in the
    /// order they lie. The control panels stand further out for a longer row, and in the dice edit
    /// mode each die has the popover that removes it.
    func setSeatDice(setIndices: [Int]) {
        guard seatDiceSetIndices != setIndices else { return }
        seatDiceSetIndices = setIndices
        seatDiceCount = setIndices.count
#if os(visionOS)
        updateSeatPanelPositions()
        updateDiceEditPopovers()
#endif
    }
}

#if os(visionOS)
extension GameTableModel {
    /// Registers the SwiftUI attachment used for a seat panel. See `TableSeatPanelAnchor`.
    func registerSeatPanel(_ attachment: Entity, for panel: TableSeatPanel) {
        // The panels cancel the table's scale, which changes with the pinch gesture.
        renderer.scaleDidChange = { [weak self] scale in
            self?.seatPanelTableScale = scale
            self?.updateSeatPanelPositions()
        }
        seatPanelTableScale = renderer.root.scale.x
        seatPanelAnchors[panel].register(attachment, in: renderer.root)
        updateSeatPanelPositions()
    }

    /// A panel view reports its own size, in meters, whenever its layout changes.
    func seatPanelSizeChanged(_ size: SIMD2<Float>, for panel: TableSeatPanel) {
        if seatPanelAnchors[panel].sizeChanged(size) {
            updateSeatPanelPositions()
        }
    }

    /// Detaches the panels from the persisted table root before their `RealityView` tears down.
    func detachSeatPanels() {
        for panel in TableSeatPanel.allCases {
            seatPanelAnchors[panel].detach()
        }
    }

    /// The gap between a dock and the panel above it, in the world's meters.
    private static let seatPanelGap = 0.03

    /// Stands the panels at the local seat, at a constant physical size: the dock and the groups'
    /// panels where the map starts, the map dock and the map controls where it ends.
    func updateSeatPanelPositions() {
        let radians = localSeatPose.rotation.radians
        let scale = max(seatPanelTableScale, 0.01)
        // A panel's width in table meters: the table's own scale shrinks it, its counter-scale
        // brings that back to the world size the view reported.
        let counter = 1 / scale
        let footprint = mapFootprint

        for panel in TableSeatPanel.allCases {
            let anchor = seatPanelAnchors[panel]
            let width = Double(anchor.size.x * counter)
            guard width > 0 else { continue }
            anchor.setScale(counter)
            // A panel that opens above a dock continues the dock's slope.
            let stack = panel.opensAbove.map {
                Double(seatPanelAnchors[$0].size.y * counter) + Self.seatPanelGap * Double(counter)
            } ?? 0
            anchor.place(TableSeatControlsLayout.edgeAlignedPlacement(
                side: panel.side,
                rotation: radians,
                edgeLateral: TableSeatControlsLayout.mapEdge(
                    panel.side,
                    rotation: radians,
                    planeWidth: Double(footprint.width),
                    planeDepth: Double(footprint.depth)
                ),
                width: width,
                stackedAbove: stack
            ))
        }
    }

    /// The local seat's pose; the game master's own seat for an observer without one.
    var localSeatPose: TableVisualState.Pose2D {
        localSeat.flatMap { seat in setup.seats.first(where: { $0.id == seat })?.initialState.pose }
            ?? PlayerSeat.seatPoses[0]
    }
}
#endif
#endif
