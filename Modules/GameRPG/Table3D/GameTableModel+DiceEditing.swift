// @copyright André Trettin

#if os(visionOS)
import Foundation
import RealityKit
import Spatial
import TabletopKit

// The dice edit mode on the 3D table (`DiceDisplayModel.isEditing`, entered with the edit button
// of the dice result popover): the result popover is gone, the dice bag stands over the seat's
// dice, and every die has a popover of its own that removes it.

extension GameTableModel {
    /// How far the dice bag stands above the dice popovers: clear of the remove popovers, which
    /// are the lower ones.
    private static let diceBagLift: Float = 0.07
    /// The gap between the top of a die and the tip of its popover's arrow.
    private static let diceEditClearance: Float = 0.012

    /// Follows `DiceDisplayModel.isEditing` into the table.
    func setDiceEditing(_ isEditing: Bool) {
        guard isDiceEditing != isEditing else { return }
        isDiceEditing = isEditing
        updateDiceEditPopovers()
    }

    /// Stands the dice bag and the remove popovers over the local seat's dice, or takes them
    /// down outside the edit mode.
    ///
    /// Applied on the next turn of the main actor, not at once: this is reached from
    /// `applyDiceRoll`, which a TabletopKit callback can call inside a Core Animation commit,
    /// and enabling or disabling an attachment there aborts. See `applyDiceResultVisibility`.
    func updateDiceEditPopovers() {
        Task { @MainActor [weak self] in
            self?.applyDiceEditPopovers()
        }
    }

    private func applyDiceEditPopovers() {
        let pose = localSeatPose
        let seat = (pose.position.x, pose.position.z)
        let dieTop = GameMetrics.tableThickness + GameMetrics.maximumDieExtent + Self.diceEditClearance
        let positions = TableSeatDice.positions(
            seatPosition: seat,
            rotation: pose.rotation.radians,
            count: seatDiceCount
        )

        for (index, anchor) in diceRemoveAnchors.enumerated() {
            if isDiceEditing, positions.indices.contains(index) {
                anchor.show(at: SIMD3<Float>(Float(positions[index].x), dieTop, Float(positions[index].z)))
            } else {
                anchor.hide()
            }
        }

        // Over the middle of the row, whatever its length: a row of no dice has that spot too.
        guard isDiceEditing,
              let middle = TableSeatDice.positions(seatPosition: seat, rotation: pose.rotation.radians, count: 1).first
        else {
            diceBagAnchor.hide()
            return
        }
        diceBagAnchor.show(at: SIMD3<Float>(Float(middle.x), dieTop + Self.diceBagLift, Float(middle.z)))
    }

    // MARK: Attachments

    func registerDiceBag(_ attachment: Entity) {
        diceBagAnchor.register(attachment, in: renderer.root)
        diceBagAnchor.hide()
        updateDiceEditPopovers()
    }

    func registerDiceRemove(_ attachment: Entity, at index: Int) {
        guard diceRemoveAnchors.indices.contains(index) else { return }
        diceRemoveAnchors[index].register(attachment, in: renderer.root)
        diceRemoveAnchors[index].hide()
        updateDiceEditPopovers()
    }

    func diceBagHeightChanged(_ height: Float) {
        diceBagAnchor.attachmentHeightChanged(height)
    }

    func diceRemoveHeightChanged(_ height: Float, at index: Int) {
        guard diceRemoveAnchors.indices.contains(index) else { return }
        diceRemoveAnchors[index].attachmentHeightChanged(height)
    }

    /// Detaches the edit mode's attachments before their `RealityView` tears down — see
    /// `TablePopoverAnchor.detach()`.
    func detachDiceEditing() {
        diceBagAnchor.detach()
        diceRemoveAnchors.forEach { $0.detach() }
    }
}
#endif
