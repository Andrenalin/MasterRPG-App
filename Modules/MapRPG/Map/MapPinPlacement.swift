// @copyright André Trettin

import CharacterRPG
import CoreGraphics
import CoreRPG
import Foundation

/// Shared monster-pin spawning and cascade-placement math. Previously
/// reimplemented independently in `EditController`, `MapEditController`, and
/// `MapEditorSession` — see CODE_AUDIT §9.3/§9.4. The cascade intentionally
/// advances both axes by the same step, so successive pins fan out
/// diagonally rather than stacking in a single horizontal row.
enum MapPinPlacement {
    static let maximumMonstersPerDrop = 25

    private static let entryInsetFractionX: CGFloat = 0.25
    private static let entryInsetFractionY: CGFloat = 0.5
    private static let interPinGap: CGFloat = 5

    @MainActor
    static func spawnPins(
        monsters: [ItemRowModel],
        count: Int,
        location: CGPoint?,
        characterRoot: CharacterRootModel
    ) -> [MapPinModel] {
        let pinCount = min(max(1, count), maximumMonstersPerDrop)
        var pins: [MapPinModel] = []
        for _ in 0..<pinCount {
            pins.append(contentsOf: monsters.map { monster in
                MapPinModel(
                    id: UUID(),
                    name: characterRoot.linkControllable.name(for: monster.itemId),
                    color: .random,
                    photoId: characterRoot.valueGameControllable.imageIds(for: monster.itemId).randomElement(),
                    characterId: monster.itemId,
                    location: location ?? .zero,
                    size: .normal,
                    isShown: true
                )
            })
        }
        return pins
    }

    /// One pin per photo, showing that photo. Unlike a monster pin it is linked to no character:
    /// `characterId` stays `nil`.
    static func spawnPhotoPins(
        photos: [(photoId: UUID, name: String)],
        location: CGPoint?
    ) -> [MapPinModel] {
        photos.prefix(maximumMonstersPerDrop).map { photo in
            MapPinModel(
                id: UUID(),
                name: photo.name,
                color: .random,
                photoId: photo.photoId,
                characterId: nil,
                location: location ?? .zero,
                size: .normal,
                isShown: true
            )
        }
    }

    /// Cascades unpositioned pins (`location == .zero`) diagonally, starting
    /// near the entry's left-center, each offset from the previous pin by its
    /// own width (scaled) plus `interPinGap` on both axes. Already-positioned
    /// pins pass through unchanged.
    ///
    /// A spot that another pin of `occupied` (or an earlier pin of this call) already stands on
    /// is skipped, and a diagonal that would leave the entry starts again one step further
    /// right, so many pins stay inside the room. When the room has no free spot left a pin takes
    /// the last candidate rather than being dropped.
    static func cascade(
        pins: [MapPinModel],
        in entry: MapEntryModel,
        pinScale: CGFloat,
        occupied: [CGPoint] = []
    ) -> [MapPinModel] {
        let start = CGPoint(
            x: entry.xOffset + entry.size.width * entryInsetFractionX,
            y: entry.yOffset + entry.size.height * entryInsetFractionY
        )
        let bounds = CGRect(origin: CGPoint(x: entry.xOffset, y: entry.yOffset), size: entry.size)
        var cursor = start
        var lane = 0
        var taken = occupied
        return pins.map { pin in
            var updated = pin
            guard updated.location == .zero else { return updated }
            let step = updated.size.size.width * pinScale + interPinGap
            let inner = bounds.insetBy(dx: step / 2, dy: step / 2)
            // A room too small for two pins cannot hold a bounded cascade: fan out as before.
            let staysInRoom = inner.contains(start) && inner.contains(CGPoint(x: start.x + step, y: start.y + step))
            var attempts = 0
            while attempts < maximumPlacementAttempts,
                  isOccupied(cursor, by: taken, step: step) || (staysInRoom && !inner.contains(cursor)) {
                attempts += 1
                var next = CGPoint(x: cursor.x + step, y: cursor.y + step)
                if staysInRoom, !inner.contains(next) {
                    // The diagonal left the room: the next one starts at the top, one step further right.
                    lane += 1
                    next = CGPoint(x: inner.minX + CGFloat(lane) * step, y: inner.minY)
                    // The room is full: the pin takes the last candidate instead of being dropped.
                    if next.x > inner.maxX { break }
                }
                cursor = next
            }
            updated.location = cursor
            taken.append(cursor)
            cursor = CGPoint(x: cursor.x + step, y: cursor.y + step)
            return updated
        }
    }

    /// Places unpositioned pins (`location == .zero`) as a diagonal group around the center of a
    /// canvas, for a map without a room to put them in. Pins that already stand somewhere pass
    /// through unchanged; a spot another pin occupies is skipped like in `cascade`.
    static func centered(
        pins: [MapPinModel],
        in canvas: CGSize,
        pinScale: CGFloat,
        occupied: [CGPoint] = []
    ) -> [MapPinModel] {
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let unpositioned = pins.filter { $0.location == .zero }
        guard !unpositioned.isEmpty else { return pins }
        let steps = unpositioned.map { $0.size.size.width * pinScale + interPinGap }
        // The group is centered by its total diagonal extent.
        let extent = steps.dropLast().reduce(0, +)
        var cursor = CGPoint(x: center.x - extent / 2, y: center.y - extent / 2)
        var taken = occupied
        return pins.map { pin in
            var updated = pin
            guard updated.location == .zero else { return updated }
            let step = updated.size.size.width * pinScale + interPinGap
            var attempts = 0
            while attempts < maximumPlacementAttempts, isOccupied(cursor, by: taken, step: step) {
                attempts += 1
                cursor = CGPoint(x: cursor.x + step, y: cursor.y + step)
            }
            updated.location = cursor
            taken.append(cursor)
            cursor = CGPoint(x: cursor.x + step, y: cursor.y + step)
            return updated
        }
    }

    private static let maximumPlacementAttempts = 400

    private static func isOccupied(_ point: CGPoint, by taken: [CGPoint], step: CGFloat) -> Bool {
        taken.contains { abs($0.x - point.x) < step * 0.75 && abs($0.y - point.y) < step * 0.75 }
    }
}
