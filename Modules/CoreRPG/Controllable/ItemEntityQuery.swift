// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import Foundation

/// Shared `EntityQuery` CRUD skeleton for the item-backed `AppIntents`
/// `Entity` types (Pdf/Photo/Space/Audio/Character/Rule/Dice/Generator/Map/
/// Table/Weather/Adventure) — every module previously hand-duplicated the
/// same `suggestedEntities`/`entities(for:)`/`entities(matching:)`/
/// `allEntities` bodies verbatim, differing only in the concrete
/// `Entity`/`Root`/`Model` types. See CODE_AUDIT_10 §9.3.
///
/// Deliberately scoped to just this query CRUD — the `Entity` struct's own
/// `AppIntents` conformances (`displayRepresentation`, `Transferable`,
/// `attributeSet`, `sharePreview`) stay hand-written per module. That's
/// where real per-module content lives (different export formats, icons,
/// Spotlight keywords) and where a shared generic base would carry the
/// Siri/Shortcuts/Spotlight regression risk 9 prior audit rounds
/// deliberately declined to take on without device-level verification —
/// see the audit's own §9.3 reasoning.
///
/// A conformer supplies `root`, `makeEntity(root:model:)`, `allIds(root:)`,
/// and `model(root:id:)`. `matches(model:text:)` and `include(model:)` have
/// defaults and are overridden only where a module's behavior genuinely
/// differs — e.g. `RuleEntityQuery` excludes `specialCategory` items via
/// `include(model:)`, `DiceEntityQuery` widens `matches(model:text:)` to
/// also search tags. `suggestedEntities()`/`entities(matching:)`/etc. are
/// protocol *requirements* (not just extension-only defaults), so a
/// conformer with genuinely different control flow — `RuleEntityQuery`
/// prefixes its result list only *after* filtering, `DiceEntityQuery` adds
/// a result cache — can still override the whole method and have every
/// call site (including from within this shared code, e.g.
/// `entities(matching:)`'s empty-string fallback to `suggestedEntities()`)
/// dispatch to that override correctly, the same reasoning as
/// `FileVersionGameControllable.rebuildFileReports`.
@MainActor
public protocol ItemEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery where Entity.ID == UUID {
    associatedtype Root
    associatedtype Model: ItemDataAccessable

    var root: Root { get }

    static var suggestedLimit: Int { get }
    static var matchingLimit: Int { get }

    func makeEntity(root: Root, model: Model) -> Entity
    func allIds(root: Root) -> [UUID]
    func model(root: Root, id: UUID) -> Model?

    /// Text-match predicate for `entities(matching:)`. Default: name or
    /// description contains `text`.
    func matches(model: Model, text: String) -> Bool

    /// Extra inclusion filter applied everywhere a `Model` is turned into
    /// an `Entity` — `entities(for:)` included. Default: always include.
    func include(model: Model) -> Bool
}

public extension ItemEntityQuery {
    static var suggestedLimit: Int { 20 }
    static var matchingLimit: Int { 25 }

    func matches(model: Model, text: String) -> Bool {
        model.name.localizedStandardContains(text) || model.description.localizedStandardContains(text)
    }

    func include(model: Model) -> Bool { true }

    func suggestedEntities() async throws -> [Entity] {
        await DatabaseReadiness.wait()
        var results: [Entity] = []
        for id in allIds(root: root).prefix(Self.suggestedLimit) {
            guard let model = model(root: root, id: id), include(model: model) else { continue }
            results.append(makeEntity(root: root, model: model))
        }
        return results
    }

    func entities(for identifiers: [Entity.ID]) async throws -> [Entity] {
        await DatabaseReadiness.wait()
        var results: [Entity] = []
        for id in identifiers {
            guard let model = model(root: root, id: id), include(model: model) else { continue }
            results.append(makeEntity(root: root, model: model))
        }
        return results
    }

    func entities(matching text: String) async throws -> [Entity] {
        await DatabaseReadiness.wait()
        guard !text.isEmpty else { return try await suggestedEntities() }
        var results: [Entity] = []
        for id in allIds(root: root) {
            guard let model = model(root: root, id: id), include(model: model), matches(model: model, text: text) else { continue }
            results.append(makeEntity(root: root, model: model))
            guard results.count < Self.matchingLimit else { break }
        }
        return results
    }

    func allEntities() async throws -> [Entity] {
        await DatabaseReadiness.wait()
        var results: [Entity] = []
        for id in allIds(root: root) {
            guard let model = model(root: root, id: id), include(model: model) else { continue }
            results.append(makeEntity(root: root, model: model))
        }
        return results
    }
}

#endif
