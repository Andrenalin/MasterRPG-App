// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import Foundation

/// Shared `EntityQuery` skeleton for the item-backed `AppIntents` entity types (all twelve
/// modules): `suggestedEntities`, `entities(for:)`, `entities(matching:)`, `allEntities` and, on
/// the 27 releases, the `displayRepresentations(for:)` fast path. Only the query is shared; each
/// entity struct keeps its own `displayRepresentation`, `Transferable`, `attributeSet` and URL
/// representation, which is where the per-module content lives.
///
/// A conformer supplies `root`, `makeEntity(root:model:)`, `allIds(root:)` and `model(root:id:)`.
/// `matches(model:text:)`, `include(model:)` and `thumbnailData(root:id:)` have defaults and are
/// overridden only where a module differs: `RuleEntityQuery` excludes `specialCategory` items,
/// `DiceEntityQuery` also searches tags, the four image modules supply cached thumbnails. The
/// `suggestedEntities`/`entities(matching:)`/... methods are protocol requirements, so a
/// conformer with different control flow can override the whole method and every call site in
/// this shared code dispatches to it.
@MainActor
public protocol ItemEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery where Entity.ID == UUID {
    associatedtype Root
    associatedtype Model: ItemDataAccessible

    var root: Root { get }

    static var suggestedLimit: Int { get }
    static var matchingLimit: Int { get }

    func makeEntity(root: Root, model: Model) -> Entity
    func allIds(root: Root) -> [UUID]
    func model(root: Root, id: UUID) -> Model?

    /// The cached list thumbnail of an item, encoded for a `DisplayRepresentation`, or `nil` for the
    /// modules without images and for items whose thumbnail is not cached (it is never generated
    /// here: resolving a disambiguation list must not decode files). Default: `nil`.
    func thumbnailData(root: Root, id: UUID) -> Data?

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

    func thumbnailData(root: Root, id: UUID) -> Data? { nil }

    func matches(model: Model, text: String) -> Bool {
        model.name.localizedStandardContains(text) || model.description.localizedStandardContains(text)
    }

    /// Excludes items the user already moved to the trash by default — Siri and
    /// Shortcuts could otherwise list, open, append to or delete an item that's
    /// already marked for deletion (only `RuleEntity` used to override this).
    /// See CODE_AUDIT_17 §5.12.
    func include(model: Model) -> Bool {
        model.displayState != DisplayStateMask.totalHidden.rawValue
    }

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

    /// Titles and icons for the items a view shows on screen, read from the model alone: Siri
    /// resolves "open the third one" with this and does not need the entity's tags, folder state or
    /// text excerpt. `entities(for:)` stays the path for running an intent. The image is the
    /// item's cached thumbnail when there is one, else the symbol the entities use: the category's
    /// for folders and collections, the module's otherwise. See CODE_AUDIT_AppIntents2 §4.6.
    /// See CODE_AUDIT_AppIntents2 §4.3.
    ///
    /// It does not wait for the database: the rows Siri asks about are on screen, so their models
    /// are in memory, and an item that is not loaded yet is simply left out instead of making Siri
    /// wait. The subtitle follows `IntentEntityText.subtitle`, like the entities' own.
    /// See CODE_AUDIT_AppIntents3 §4.11, §7.1.
    @available(iOS 27, macOS 27, visionOS 27, *)
    func displayRepresentations(for identifiers: [Entity.ID]) async throws -> [Entity.ID: DisplayRepresentation] {
        var results: [Entity.ID: DisplayRepresentation] = [:]
        for id in identifiers {
            guard let model = model(root: root, id: id), include(model: model) else { continue }
            let icon = model.specialCategory ? model.category.icon : Model.typeId.icon
            let image: DisplayRepresentation.Image = thumbnailData(root: root, id: id).map { .init(data: $0) } ?? .init(systemName: icon)
            let subtitle = IntentEntityText.subtitle(of: model) { self.model(root: root, id: $0) }
            results[id] = DisplayRepresentation(
                title: "\(model.name)",
                subtitle: subtitle.isEmpty ? nil : "\(subtitle)",
                image: image
            )
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
