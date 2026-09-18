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

    /// Cascades unpositioned pins (`location == .zero`) diagonally, starting
    /// near the entry's left-center, each offset from the previous pin by its
    /// own width (scaled) plus `interPinGap` on both axes. Already-positioned
    /// pins pass through unchanged.
    static func cascade(pins: [MapPinModel], in entry: MapEntryModel, pinScale: CGFloat) -> [MapPinModel] {
        var leftCenter = CGPoint(
            x: entry.xOffset + entry.size.width * entryInsetFractionX,
            y: entry.yOffset + entry.size.height * entryInsetFractionY
        )
        return pins.map { pin in
            var updated = pin
            if updated.location == .zero {
                updated.location = leftCenter
                let step = updated.size.size.width * pinScale + interPinGap
                leftCenter = CGPoint(
                    x: leftCenter.x + step,
                    y: leftCenter.y + step
                )
            }
            return updated
        }
    }
}
