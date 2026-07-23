// @copyright André Trettin

import Foundation

/// One component in the editable hierarchy of a Foundry JSON value or dotted rule path.
public struct FoundryValueNode: Equatable, Sendable {
    public let component: String
    public let pathComponents: [String]
    public let value: FoundryJSONValue?
    public let children: [FoundryValueNode]

    public init(
        component: String,
        pathComponents: [String],
        value: FoundryJSONValue?,
        children: [FoundryValueNode]
    ) {
        self.component = component
        self.pathComponents = pathComponents
        self.value = value
        self.children = children
    }

    public var path: String {
        pathComponents.joined(separator: ".")
    }

    public var isGroup: Bool {
        !children.isEmpty
    }

    public var valueCount: Int {
        (value == nil ? 0 : 1) + children.reduce(0) { $0 + $1.valueCount }
    }
}

/// Builds deterministic nested groups instead of exposing implementation paths as dotted labels.
///
/// For example, `attributes.body.base = 5` becomes the group `attributes`, containing the group
/// `body`, containing the editable value `base = 5`.
public enum FoundryValueHierarchy {
    public static func nodes(from value: FoundryJSONValue) -> [FoundryValueNode] {
        switch value {
        case .object(let object):
            return object.keys.sorted(by: componentSort).compactMap { component in
                object[component].map {
                    node(from: $0, component: component, parentPath: [])
                }
            }
        case .array(let values):
            return values.enumerated().map { index, value in
                node(from: value, component: String(index), parentPath: [])
            }
        default:
            return [
                FoundryValueNode(
                    component: "value",
                    pathComponents: [],
                    value: value,
                    children: []
                )
            ]
        }
    }

    public static func nodes(from values: [FoundryRuleValue]) -> [FoundryValueNode] {
        var root = NodeBuilder()
        for value in values {
            let components = value.path
                .split(separator: ".", omittingEmptySubsequences: true)
                .map(String.init)
            guard !components.isEmpty else { continue }
            root.insert(value.value, at: ArraySlice(components))
        }
        return root.materializedChildren(parentPath: [])
    }
}

private extension FoundryValueHierarchy {
    struct NodeBuilder {
        var value: FoundryJSONValue?
        var children: [String: NodeBuilder] = [:]

        mutating func insert(_ value: FoundryJSONValue, at components: ArraySlice<String>) {
            guard let component = components.first else {
                self.value = value
                return
            }
            var child = children[component] ?? NodeBuilder()
            child.insert(value, at: components.dropFirst())
            children[component] = child
        }

        func materializedChildren(parentPath: [String]) -> [FoundryValueNode] {
            children.keys.sorted(by: FoundryValueHierarchy.componentSort).compactMap { component in
                children[component]?.materialized(
                    component: component,
                    parentPath: parentPath
                )
            }
        }

        func materialized(component: String, parentPath: [String]) -> FoundryValueNode {
            let path = parentPath + [component]
            return FoundryValueNode(
                component: component,
                pathComponents: path,
                value: value,
                children: materializedChildren(parentPath: path)
            )
        }
    }

    static func node(
        from value: FoundryJSONValue,
        component: String,
        parentPath: [String]
    ) -> FoundryValueNode {
        let path = parentPath + [component]
        switch value {
        case .object(let object):
            let children = object.keys.sorted(by: componentSort).compactMap { childComponent in
                object[childComponent].map {
                    node(from: $0, component: childComponent, parentPath: path)
                }
            }
            return FoundryValueNode(
                component: component,
                pathComponents: path,
                value: nil,
                children: children
            )
        case .array(let values):
            let children = values.enumerated().map { index, child in
                node(from: child, component: String(index), parentPath: path)
            }
            return FoundryValueNode(
                component: component,
                pathComponents: path,
                value: nil,
                children: children
            )
        default:
            return FoundryValueNode(
                component: component,
                pathComponents: path,
                value: value,
                children: []
            )
        }
    }

    static func componentSort(_ lhs: String, _ rhs: String) -> Bool {
        if let lhsNumber = UInt(lhs), let rhsNumber = UInt(rhs) {
            return lhsNumber < rhsNumber
        }
        return lhs < rhs
    }
}
