// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import Foundation

/// The matching, sorting and limiting behind the Find action of an `EntityPropertyQuery`, shared
/// by the modules that adopt one so each keeps only its property table. See
/// CODE_AUDIT_AppIntents §4.5.
public extension ItemEntityQuery {
    /// The entities that satisfy `predicates` (all of them for `.and`, any for `.or`), sorted by
    /// name when `nameAscending` is set (`nil` keeps the item order), and cut to `limit`. Trashed items are excluded like
    /// everywhere else an item becomes an entity.
    func findEntities(
        matching predicates: [Predicate<Entity>],
        mode: EntityQueryComparatorMode,
        nameAscending: Bool?,
        name: (Entity) -> String,
        limit: Int?
    ) async throws -> [Entity] {
        await DatabaseReadiness.wait()
        var results: [Entity] = []
        for id in allIds(root: root) {
            guard let model = model(root: root, id: id), include(model: model) else { continue }
            let entity = makeEntity(root: root, model: model)
            let isMatch: Bool
            if predicates.isEmpty {
                isMatch = true
            } else if mode == .and {
                isMatch = try predicates.allSatisfy { try $0.evaluate(entity) }
            } else {
                isMatch = try predicates.contains { try $0.evaluate(entity) }
            }
            if isMatch { results.append(entity) }
        }

        if let nameAscending {
            results.sort { lhs, rhs in
                let order = name(lhs).localizedStandardCompare(name(rhs))
                return nameAscending ? order == .orderedAscending : order == .orderedDescending
            }
        }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }
}

#endif
