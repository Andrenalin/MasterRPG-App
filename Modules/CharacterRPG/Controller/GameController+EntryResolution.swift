// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Entry Resolution
// Split out of GameController.swift's `ValueGameStorable` conformance —
// see CODE_AUDIT_Character §9.8. Conformance itself is declared on the
// `extension GameController: ValueGameStorable` in GameController.swift;
// these are additional members satisfying that same protocol.

extension GameController {
    @MainActor
    public func gameEntry(
        matchingAny names: [String],
        characterId: UUID
    ) -> ValueEntryModel? {
        gameEntry(matchingAny: names, characterId: characterId, depth: 0)
    }

    @MainActor
    private func gameEntry(
        matchingAny names: [String],
        characterId: UUID,
        depth: Int
    ) -> ValueEntryModel? {
        guard depth < RecursionLimits.maxValueLinkDepth else { return nil }
        let normalizedNames = names
            .map(Self.comparableName)
            .filter { !$0.isEmpty }
        guard !normalizedNames.isEmpty else { return nil }

        let item = gameItem(for: characterId)
        if let direct = item.entries.first(where: { entry in
            let entryName = Self.comparableName(entry.name)
            return normalizedNames.contains {
                entryName.localizedCaseInsensitiveCompare($0) == .orderedSame
            }
        }) {
            return direct
        }
        if let linked = item.entries.first(where: { entry in
            LinkReplaceController.links(for: entry.value).contains { link in
                let linkName = link.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalizedNames.contains {
                    linkName.localizedCaseInsensitiveCompare($0) == .orderedSame
                }
            }
        }) {
            return linked
        }
        for entry in item.entries {
            guard let valueId = entry.valueId,
                  let found = gameEntry(matchingAny: names, characterId: valueId, depth: depth + 1) else {
                continue
            }
            return found
        }
        return nil
    }

    /// Character entry names may carry a markdown link (`nameWithLink` in
    /// `EditController.update`), so names are compared by their visible text.
    private static func comparableName(_ name: String) -> String {
        name.withoutLink().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Searches `characterId`'s own entries first, then descends into any
    /// nested value "group" tables (linked via `valueId`) — HP and other
    /// tracked values are frequently grouped, not top-level.
    @MainActor
    public func gameEntry(
        characterId: UUID,
        entryId: UUID
    ) -> ValueEntryModel? {
        gameEntry(characterId: characterId, entryId: entryId, depth: 0)
    }

    @MainActor
    private func gameEntry(characterId: UUID, entryId: UUID, depth: Int) -> ValueEntryModel? {
        guard depth < RecursionLimits.maxValueLinkDepth else { return nil }
        let item = gameItem(for: characterId)
        if let direct = item.entries.first(where: { $0.id == entryId }) {
            return direct
        }
        for entry in item.entries {
            guard let valueId = entry.valueId,
                  let found = gameEntry(characterId: valueId, entryId: entryId, depth: depth + 1) else {
                continue
            }
            return found
        }
        return nil
    }

    @MainActor
    public func gameEntryPath(itemId: UUID, entryId: UUID) -> GameEntryPath? {
        var currentItem = gameItem(for: itemId)
        var currentItemId = itemId
        guard let leafIndex = currentItem.entries.firstIndex(where: { $0.id == entryId }) else {
            return nil
        }
        let name = currentItem.entries[leafIndex].name
        var indices = [leafIndex]

        // `groupId` comes from Character data that can arrive over the
        // network (updatePlayer(data:) → importNetwork); a crafted cyclic
        // pair must not hang this loop forever. See CODE_AUDIT_Game §5.7.
        var depth = 0
        while let ownerId = currentItem.groupId {
            guard depth < RecursionLimits.maxValueLinkDepth else { return nil }
            let owner = gameItem(for: ownerId)
            guard let linkIndex = owner.entries.firstIndex(where: { $0.valueId == currentItemId }) else {
                return nil
            }
            indices.append(linkIndex)
            currentItem = owner
            currentItemId = ownerId
            depth += 1
        }

        return GameEntryPath(indices: Array(indices.reversed()), rootCharacterId: currentItemId, name: name)
    }

    @MainActor
    public func gameEntry(matching path: GameEntryPath, characterId: UUID) -> ValueEntryModel? {
        guard !path.indices.isEmpty else { return nil }
        var currentItem = gameItem(for: characterId)
        var candidate: ValueEntryModel?
        for (offset, index) in path.indices.enumerated() {
            guard currentItem.entries.indices.contains(index) else { return nil }
            let entry = currentItem.entries[index]
            candidate = entry
            if offset < path.indices.count - 1 {
                guard let valueId = entry.valueId else { return nil }
                currentItem = gameItem(for: valueId)
            }
        }
        guard let candidate,
              Self.comparableName(candidate.name)
                  .localizedCaseInsensitiveCompare(Self.comparableName(path.name)) == .orderedSame else {
            return nil
        }
        return candidate
    }

    @MainActor
    public func gameEntryDisplayValue(
        characterId: UUID,
        entryId: UUID
    ) -> String? {
        guard let entry = gameEntry(characterId: characterId, entryId: entryId) else {
            return nil
        }
        if let calculated = root.linkController.calculate(entry: entry) {
            return calculated
        }
        // A `.text` entry can still hold a value link (typed or imported; only
        // the link picker switches the entry to `.number`). Resolve it like a
        // number so callers get the linked value instead of raw markdown.
        guard LinkReplaceController.links(for: entry.value).contains(where: { $0.module == .value }),
              let resolved = calculatedValue(entry.value, type: .decimal),
              let number = Double(resolved) else {
            return entry.value
        }
        return number == number.rounded() && abs(number) < Double(Int.max)
            ? "\(Int(number))"
            : resolved
    }

    @MainActor
    public func calculatedValue(_ text: String, type: ValueEntryModel.ValueType) -> String? {
        // A synthetic, unstored entry: `LinkController.calculate(entry:)` only
        // needs `type` (for `canCalculate`) and `value` (to scan for links and
        // evaluate) — it doesn't require the entry to actually exist anywhere.
        let entry = ValueEntryModel(id: UUID(), name: "", type: type, value: text)
        return root.linkController.calculate(entry: entry) ?? text
    }

    /// Game-memory copy of `itemId`, promoting one from persistence on first
    /// touch — the shared half of `applyGameValueEntryUpdate`'s two
    /// resolution paths. A player's Character is normally imported into the
    /// master's item store during join; this is what makes the *first* live
    /// value update (whichever item it targets) promote a copy into game
    /// memory so gameplay changes never mutate persistence.
    @MainActor
    func gameMemoryCopy(for itemId: UUID) -> ValueModel? {
        if let current = gameModel.itemData[itemId] as? ValueModel {
            return current
        }
        guard let stored = itemController.itemSync(for: itemId)?.copy() else { return nil }
        gameModel.itemData[itemId] = stored
        return stored
    }

    /// Walks `path` (root-to-leaf indices, from `GameEntryPath.indices`) to
    /// the `ValueModel` that actually owns the leaf entry, together with its
    /// index in that model's own `entries` — the mutation must land on
    /// whichever nested group actually owns the entry, not necessarily
    /// `rootCharacterId`'s own top-level entries. See CODE_AUDIT_Game §5.3.
    @MainActor
    func resolveGroupedEntry(
        rootCharacterId: UUID,
        path: [Int]
    ) -> (owner: ValueModel, index: Int)? {
        guard !path.isEmpty, var currentItem = gameMemoryCopy(for: rootCharacterId) else { return nil }
        for (offset, index) in path.enumerated() {
            guard currentItem.entries.indices.contains(index) else { return nil }
            if offset == path.count - 1 {
                return (currentItem, index)
            }
            guard let valueId = currentItem.entries[index].valueId,
                  let nested = gameMemoryCopy(for: valueId) else { return nil }
            currentItem = nested
        }
        return nil
    }
}
