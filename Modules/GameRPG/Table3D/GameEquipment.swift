// @copyright André Trettin

#if os(visionOS)
import TabletopKit

extension EquipmentIdentifier {
    static var tableId: Self { .init(0) }
}

struct Table: Tabletop {
    // `width` is TabletopKit's X-extent, `height` its Z-extent (matching
    // `TableAssetFactory.makePlainWoodTable()`'s own `generateBox(width:height:depth:)`
    // call for the same mesh). The table's long dimension runs along Z
    // (`tableLength`), not X, so the long sides recede away from the
    // viewer instead of spanning left-right in front of them — see
    // `PlayerSeat.seatPoses`'s own doc for the seat layout this supports.
    //
    // `thickness` is doubled on purpose: TabletopKit centres its slab on the parent entity's
    // origin, so its top — where it rests the bottom of every die's bounding box — is at
    // `thickness / 2`. The wood mesh is bottom-origin (top at `tableThickness`), which left
    // the dice sunk half a table thickness (7.3 mm) into the wood.
    var shape: TabletopShape = .rectangular(
        width: GameMetrics.tableWidth,
        height: GameMetrics.tableLength,
        thickness: GameMetrics.tableThickness * 2
    )

    var id: EquipmentIdentifier = .tableId
}

#endif
