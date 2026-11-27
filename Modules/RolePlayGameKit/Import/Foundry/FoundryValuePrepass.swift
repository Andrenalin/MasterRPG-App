// @copyright André Trettin

import CoreRPG
import Foundation

/// A field of a document's `system` data, flattened and with its ids derived, so the main actor
/// only builds the models. See CODE_AUDIT_29 §3.4.
struct FoundryValuePlanNode: Sendable {
    /// The decoded field name.
    let name: String
    let value: FoundryJSONValue?
    let children: [FoundryValuePlanNode]
    /// The entry id of a leaf field.
    let fieldId: UUID
    /// The group model, its own value's entry and the link entry of a field with children.
    let groupIds: (group: UUID, value: UUID, link: UUID)?
    let valueCount: Int
}

/// Flattens the `system` values of the actors and items and derives their stable ids before the
/// models are built, off the main actor, as `FoundryTextPrepass` does for the descriptions.
/// See CODE_AUDIT_29 §3.4.
enum FoundryValuePrepass {
    /// The `system` values the mapper turns into value entries, keyed by source document id.
    /// An id that appears with two different values is left out (the mapper plans it itself).
    static func sources(documents: [FoundryDocument]) -> [String: FoundryJSONValue] {
        var sources: [String: FoundryJSONValue] = [:]
        var ambiguous: Set<String> = []
        for document in documents where document.documentType == .actor || document.documentType == .item {
            guard let system = document.rawData["system"], !ambiguous.contains(document.id) else { continue }
            if let existing = sources[document.id], existing != system {
                sources[document.id] = nil
                ambiguous.insert(document.id)
            } else {
                sources[document.id] = system
            }
        }
        return sources
    }

    @concurrent
    static func plans(of sources: [String: FoundryJSONValue], scope: UUID) async -> [String: FoundryValuePlan] {
        var result: [String: FoundryValuePlan] = [:]
        result.reserveCapacity(sources.count)
        for (sourceId, value) in sources {
            if Task.isCancelled { break }
            result[sourceId] = FoundryValuePlan(value: value, nodes: plan(value, sourceId: sourceId, scope: scope))
        }
        return result
    }

    static func plan(_ value: FoundryJSONValue, sourceId: String, scope: UUID) -> [FoundryValuePlanNode] {
        FoundryValueHierarchy.nodes(from: value).map { plan($0, sourceId: sourceId, scope: scope) }
    }

    private static func plan(_ node: FoundryValueNode, sourceId: String, scope: UUID) -> FoundryValuePlanNode {
        let pathIdentity = valuePathIdentity(node.pathComponents)
        let children = node.children.map { plan($0, sourceId: sourceId, scope: scope) }
        let isLeaf = node.children.isEmpty && node.value != nil
        return FoundryValuePlanNode(
            name: FoundryTextDecoder.decodedText(node.component),
            value: node.value,
            children: children,
            fieldId: stableId("\(sourceId)#field#\(pathIdentity)", scope: scope),
            groupIds: isLeaf ? nil : (
                stableId("\(sourceId)#field-group#\(pathIdentity)", scope: scope),
                stableId("\(sourceId)#field#\(pathIdentity)#value", scope: scope),
                stableId("\(sourceId)#field-group-link#\(pathIdentity)", scope: scope)
            ),
            valueCount: (node.value == nil ? 0 : 1) + children.reduce(0) { $0 + $1.valueCount }
        )
    }

    /// The same id `FoundryMappingState.stableId(_:)` derives.
    static func stableId(_ component: String, scope: UUID) -> UUID {
        FoundryRuleIdentity.uuid(for: "external-source:\(scope.uuidString.lowercased())#\(component)")
    }

    static func valuePathIdentity(_ components: [String]) -> String {
        guard !components.isEmpty else { return "root" }
        return components.map { component in
            "\(component.utf8.count):\(component)"
        }.joined()
    }
}

/// The planned fields of one `system` value, with the value they were planned from.
struct FoundryValuePlan: Sendable {
    let value: FoundryJSONValue
    let nodes: [FoundryValuePlanNode]
}
