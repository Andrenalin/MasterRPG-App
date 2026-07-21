// @copyright André Trettin

import CoreRPG
import Foundation

public struct RuleEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    public init(
        id: UUID,
        name: String,
        content: String,
        kind: RuleEntryKind = .text,
        displayState: Int = 0
    ) {
        self.id = id
        _name = CRDT(wrappedValue: name)
        _content = CRDT(wrappedValue: content)
        _kind = CRDT(wrappedValue: kind)
        self.displayState = displayState
    }

    init(
        id: UUID,
        name: CRDT<String>,
        content: CRDT<String>,
        kind: CRDT<RuleEntryKind>,
        displayState: Int
    ) {
        self.id = id
        _name = name
        _content = content
        _kind = kind
        self.displayState = displayState
    }

    public let id: UUID
    @CRDT public var name: String
    @CRDT public var content: String
    @CRDT public var kind: RuleEntryKind
    public var displayState: Int
}

extension RuleEntryModel: EntryDataAccessable {
    public var childId: UUID { id }

    public static func newChild(id: UUID) -> RuleEntryModel {
        empty(id)
    }

    public static var empty: RuleEntryModel { empty(UUID()) }

    public static func empty(_ id: UUID) -> RuleEntryModel {
        RuleEntryModel(id: id, name: "", content: "")
    }

    public func duplicate() -> RuleEntryModel {
        RuleEntryModel(
            id: UUID(),
            name: name,
            content: content,
            kind: kind,
            displayState: displayState
        )
    }

    public func filter(with search: String) -> Bool {
        search.isEmpty || name.localizedStandardContains(search) || content.localizedStandardContains(search)
    }

    public func linkContent() -> String { content }
}

extension RuleEntryModel: ItemDiffComparable {
    public func merge(_ other: RuleEntryModel) -> RuleEntryModel {
        RuleEntryModel(
            id: id,
            name: $name.merged(other: other.$name),
            content: $content.merged(other: other.$content),
            kind: $kind.merged(other: other.$kind),
            displayState: other.displayState
        )
    }

    public func isSame(_ other: RuleEntryModel) -> Bool {
        name == other.name && content == other.content && kind == other.kind
    }
}

extension RuleEntryModel: ItemLinkEditable {
    public var textLinkContent: String {
        name.isEmpty ? content : "**\(name.trimmingCharacters(in: .whitespacesAndNewlines))**: \(content)"
    }
}

extension RuleEntryModel: ItemReferencable {}

#if DEBUG
public extension RuleEntryModel {
    static func fixture(
        id: UUID = UUID(),
        name: String = "Rule section",
        content: String = "Rule content",
        kind: RuleEntryKind = .text,
        displayState: Int = 0
    ) -> RuleEntryModel {
        RuleEntryModel(
            id: id,
            name: name,
            content: content,
            kind: kind,
            displayState: displayState
        )
    }
}
#endif

