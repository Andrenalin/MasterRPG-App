// @copyright André Trettin

import CharacterRPG
import CoreGraphics
import CoreRPG
import Foundation

/// Shared monster-pin spawning and cascade-placement math. Previously
/// reimplemented independently in `EditController`, `MapEditController`, and
/// `MapEditorSession` — see CODE_AUDIT §9.3/§9.4. Consolidating here also
/// fixes the diagonal-drift bug from CODE_AUDIT §5.1: the old inline math
/// used `CGPoint + CGFloat`, which adds the offset to both axes instead of
/// advancing x only.
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

    /// Cascades unpositioned pins (`location == .zero`) in a horizontal row
    /// starting near the entry's left-center, each offset from the previous
    /// pin by its own width (scaled) plus `interPinGap`. Already-positioned
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
                leftCenter = CGPoint(
                    x: leftCenter.x + updated.size.size.width * pinScale + interPinGap,
                    y: leftCenter.y
                )
            }
            return updated
        }
    }
}
