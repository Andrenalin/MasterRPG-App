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
    var shape: TabletopShape = .rectangular(
        width: GameMetrics.tableWidth,
        height: GameMetrics.tableLength,
        thickness: GameMetrics.tableThickness
    )

    var id: EquipmentIdentifier = .tableId
}

#endif
