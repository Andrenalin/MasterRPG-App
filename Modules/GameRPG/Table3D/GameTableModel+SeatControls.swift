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

    /// Called when the shown map changes: opens the map controls for the first map. The panels
    /// themselves stand at the margins of the biggest map the table takes, so they do not move.
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
    /// panels where the biggest map starts, the map dock and the map controls where it ends.
    func updateSeatPanelPositions() {
        let pose = localSeatPose
        let radians = pose.rotation.radians
        let seatLateral = TableSeatControlsLayout.seatLateral(
            seatPosition: (pose.position.x, pose.position.z), rotation: radians
        )
        // The dice row's extent along the edge, plus a die's own width at each end.
        let diceRowWidth = seatDiceCount > 0 ? TableSeatDice.spacing * Double(seatDiceCount) : 0
        let scale = max(seatPanelTableScale, 0.01)
        // A panel's width in table meters: the table's own scale shrinks it, its counter-scale
        // brings that back to the world size the view reported.
        let counter = 1 / scale

        for panel in TableSeatPanel.allCases {
            let anchor = seatPanelAnchors[panel]
            let width = Double(anchor.size.x * counter)
            guard width > 0 else { continue }
            anchor.setScale(counter)
            // A panel that opens above a dock continues the dock's slope.
            let stack = stackHeight(above: panel, counter: counter)
            // A seat on a long side stands off-centre on its edge. Its panels belong beside its
            // own dice, toward the corner: the controls on the outer side of the seat, the map
            // controls (the game master's, who is never on a side) on the other.
            if let outer = TableSeatControlsLayout.outerSide(seatLateral: seatLateral) {
                anchor.place(TableSeatControlsLayout.besideDiceRowPlacement(
                    side: panel.side == .leading ? outer : outer.opposite,
                    rotation: radians,
                    seatLateral: seatLateral,
                    rowWidth: diceRowWidth,
                    width: width,
                    gap: Self.seatPanelGap * Double(counter),
                    stackedAbove: stack
                ))
                continue
            }
            anchor.place(TableSeatControlsLayout.edgeAlignedPlacement(
                side: panel.side,
                rotation: radians,
                // The biggest map the table takes, not the shown one: the panels stay at the
                // margins whatever the map's size.
                edgeLateral: TableSeatControlsLayout.mapEdge(
                    panel.side,
                    rotation: radians,
                    planeWidth: Double(MapTableProjection.maxPlaneWidth),
                    planeDepth: Double(MapTableProjection.maxPlaneDepth)
                ),
                width: width,
                stackedAbove: stack
            ))
        }
    }

    /// How high up the slope a panel stands: the heights of the panels it opens above, and the
    /// ones those open above (the volume slider stands over the controls panel, over the dock),
    /// with a gap each. A closed panel has no height and no gap.
    private func stackHeight(above panel: TableSeatPanel, counter: Float) -> Double {
        var total = 0.0
        var below = panel.opensAbove
        while let current = below {
            let height = Double(seatPanelAnchors[current].size.y * counter)
            if height > 0 {
                total += height + Self.seatPanelGap * Double(counter)
            }
            below = current.opensAbove
        }
        return total
    }

    /// The local seat's pose; the game master's own seat for an observer without one.
    var localSeatPose: TableVisualState.Pose2D {
        localSeat.flatMap { seat in setup.seats.first(where: { $0.id == seat })?.initialState.pose }
            ?? PlayerSeat.seatPoses[0]
    }
}
#endif
#endif
