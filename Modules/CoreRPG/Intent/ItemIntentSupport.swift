// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import Foundation

// The bodies the twelve modules' intents used to copy: the target lookup before and after a write,
// the Update intent, the Open route, the support registration, the incremental reindex and the
// `IndexedEntityQuery` methods. Each module keeps what App Intents metadata extraction reads from
// its own binary (the intent structs with their titles, descriptions, summaries, `@Parameter`s and
// a `perform()` of their own) and its dialogs, which are localized from the module's bundle.
// See CODE_AUDIT_Since_3.0.1 §9.1.

/// The model behind the entity in `parameter`, looked up through the entity's `defaultQuery`. The
/// entity can be stale (deleted since Siri or Shortcuts cached it), so a missing model asks for the
/// target again instead of reporting a success that changed nothing. See CODE_AUDIT_AppIntents §5.2.
@MainActor
@discardableResult
public func requiredIntentModel<Entity: AppEntity>(
    _ parameter: IntentParameter<Entity>,
    prompt: IntentDialog,
    in root: Entity.DefaultQuery.Root
) throws -> Entity.DefaultQuery.Model where Entity.DefaultQuery: ItemEntityQuery, Entity.DefaultQuery.Entity == Entity {
    try requiredIntentTarget(Entity.defaultQuery.model(root: root, id: parameter.wrappedValue.id), parameter: parameter, prompt: prompt)
}

/// The entity in `parameter` read again after an intent changed its item, and indexed, so the
/// intent can return the updated entity and a follow-up Siri request finds the change.
/// See CODE_AUDIT_AppIntents3 §4.14.
@MainActor
public func reindexedIntentTarget<Entity: IndexedEntity>(
    _ parameter: IntentParameter<Entity>,
    prompt: IntentDialog,
    in root: Entity.DefaultQuery.Root
) async throws -> Entity where Entity.DefaultQuery: ItemEntityQuery, Entity.DefaultQuery.Entity == Entity {
    let model = try requiredIntentModel(parameter, prompt: prompt, in: root)
    let entity = Entity.defaultQuery.makeEntity(root: root, model: model)
    await indexIntentEntities([entity])
    return entity
}

/// What every Update intent does: checks the target, applies `updateIntentItem`, reads the entity
/// again and indexes it when something changed. The dialog stays with the intent.
/// See CODE_AUDIT_AppIntents3 §4.5.
@MainActor
public func updateIntentTarget<Entity: IndexedEntity>(
    _ parameter: IntentParameter<Entity>,
    prompt: IntentDialog,
    name: String?,
    description: AttributedString?,
    addTags: [String]?,
    removeTags: [String]?,
    in root: Entity.DefaultQuery.Root
) async throws -> (entity: Entity, changed: Bool)
where Entity.DefaultQuery: ItemEntityQuery, Entity.DefaultQuery.Entity == Entity, Entity.DefaultQuery.Root: ItemRootControllable {
    try requiredIntentModel(parameter, prompt: prompt, in: root)
    let changed = try await updateIntentItem(
        id: parameter.wrappedValue.id,
        name: name,
        description: description,
        addTags: addTags,
        removeTags: removeTags,
        in: root
    )
    let model = try requiredIntentModel(parameter, prompt: prompt, in: root)
    let entity = Entity.defaultQuery.makeEntity(root: root, model: model)
    if changed {
        await indexIntentEntities([entity])
    }
    return (entity, changed)
}

public extension ItemEntityQuery where Entity: IndexedEntity, Root: ItemRootControllable & AnyObject {
    /// Names the entity type the module's donations use, so they can be deleted when an item is
    /// trashed or purged, and how an item is exported as text (`document`, by default the item's
    /// own text). See CODE_AUDIT_AppIntents §4.4, CODE_AUDIT_AppIntents3 §4.1.
    static func registerIntentSupport(
        root: Root,
        document: @escaping @MainActor (Root, Model) -> String = { IntentEntityText.document(of: $1) }
    ) {
        IntentEntityIdentifiers.register(Entity.self, for: Model.typeId)
        EntitySummaryExport.register(module: Model.typeId) { [weak root] id in
            guard let root, let model = Self().model(root: root, id: id) else { return nil }
            return document(root, model)
        }
    }

    /// `reindexIntentEntities` for the module: an item the query does not `include` (trashed, or a
    /// rule category) leaves the index.
    static func reindexChanged(root: Root) async {
        let query = Self()
        await reindexIntentEntities(
            itemDataModel: root.itemControllable.itemDataModel,
            module: Model.typeId,
            model: { query.model(root: root, id: $0) },
            isIndexable: { query.include(model: $0) },
            makeEntity: { query.makeEntity(root: root, model: $0) }
        )
    }
}

/// The `IndexedEntityQuery` methods every module conformed with the same bodies. A module still
/// declares the conformance (`extension MapEntityQuery: @preconcurrency IndexedEntityQuery {}`):
/// `@preconcurrency` because `CSSearchableIndexDescription` is not `Sendable` and these methods
/// run on the main actor. See CODE_AUDIT_Table §4.1.
@available(iOS 27, macOS 27, visionOS 27, *)
public extension ItemEntityQuery where Self: IndexedEntityQuery, Entity: IndexedEntity {
    func reindexEntities(for identifiers: [Entity.ID], indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex.default().indexAppEntities(try await entities(for: identifiers))
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex.default().indexAppEntities(try await allEntities())
    }
}

/// An intent that opens one item: the legacy Open intent Shortcuts lists and its iOS 27
/// `.system.open` sibling. Each keeps its own `perform()` (metadata extraction needs one in the
/// struct) and calls `openTarget()`.
public protocol ItemOpenIntent: AppIntent {
    associatedtype Target: AppEntity
    var target: Target { get set }
    var navigator: Navigator { get }
}

public extension ItemOpenIntent where Target.DefaultQuery: ItemEntityQuery, Target.DefaultQuery.Entity == Target {
    /// Shows the target in its module.
    @MainActor
    func openTarget() async {
        let route = KnownRoutes.route(module: Target.DefaultQuery.Model.typeId, itemId: target.id, entryId: nil)
        navigator.perform(route: route)
    }

    /// The intent with `target` set, for donating it as the on-screen item. See `SiriItemContext`.
    static func opening(_ target: Target) -> Self {
        var intent = Self()
        intent.target = target
        return intent
    }
}

#endif
