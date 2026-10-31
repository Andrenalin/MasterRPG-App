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
    ///
    /// The predicates and the sort read the light `makeFindEntity`; the full entity, with its text
    /// excerpt and subtitle, is built only for the results. Without sorting the scan stops at
    /// `limit`. See CODE_AUDIT_Since_3.0.1 §7.2.
    func findEntities(
        matching predicates: [Predicate<Entity>],
        mode: EntityQueryComparatorMode,
        nameAscending: Bool?,
        name: (Entity) -> String,
        limit: Int?
    ) async throws -> [Entity] {
        await DatabaseReadiness.wait()
        var candidates: [Entity] = []
        for id in allIds(root: root) {
            if nameAscending == nil, let limit, candidates.count >= limit { break }
            guard let model = model(root: root, id: id), include(model: model) else { continue }
            let candidate = makeFindEntity(root: root, model: model)
            let isMatch: Bool
            if predicates.isEmpty {
                isMatch = true
            } else if mode == .and {
                isMatch = try predicates.allSatisfy { try $0.evaluate(candidate) }
            } else {
                isMatch = try predicates.contains { try $0.evaluate(candidate) }
            }
            if isMatch { candidates.append(candidate) }
        }

        if let nameAscending {
            candidates.sort { lhs, rhs in
                let order = name(lhs).localizedStandardCompare(name(rhs))
                return nameAscending ? order == .orderedAscending : order == .orderedDescending
            }
        }
        if let limit { candidates = Array(candidates.prefix(limit)) }
        return candidates.compactMap { candidate in
            model(root: root, id: candidate.id).map { makeEntity(root: root, model: $0) }
        }
    }
}

#endif
