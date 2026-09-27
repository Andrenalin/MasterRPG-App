// @copyright André Trettin

import CoreRPG
import Foundation

public struct RuleEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    public init(
        id: UUID,
        name: String,
        content: String,
        kind: RuleEntryKind = .text,
        displayState: Int = 0,
        parentId: UUID? = nil
    ) {
        self.id = id
        _name = CRDT(wrappedValue: name)
        _content = CRDT(wrappedValue: content)
        _kind = CRDT(wrappedValue: kind)
        self.displayState = displayState
        self.parentId = parentId
    }

    init(
        id: UUID,
        name: CRDT<String>,
        content: CRDT<String>,
        kind: CRDT<RuleEntryKind>,
        displayState: Int,
        parentId: UUID?
    ) {
        self.id = id
        _name = name
        _content = content
        _kind = kind
        self.displayState = displayState
        self.parentId = parentId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        _name = try container.decode(CRDT<String>.self, forKey: .name)
        _content = try container.decode(CRDT<String>.self, forKey: .content)
        _kind = try container.decode(CRDT<RuleEntryKind>.self, forKey: .kind)
        displayState = try container.decode(Int.self, forKey: .displayState)
        parentId = try container.decodeIfPresent(UUID.self, forKey: .parentId)
    }

    public let id: UUID
    @CRDT public var name: String
    @CRDT public var content: String
    @CRDT public var kind: RuleEntryKind
    public var displayState: Int
    public var parentId: UUID?

    private enum CodingKeys: CodingKey {
        case id
        case name
        case content
        case kind
        case displayState
        case parentId
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(_name, forKey: .name)
        try container.encode(_content, forKey: .content)
        try container.encode(_kind, forKey: .kind)
        try container.encode(displayState, forKey: .displayState)
        try container.encodeIfPresent(parentId, forKey: .parentId)
    }
}

extension RuleEntryModel: EntryDataAccessible {
    public var childId: UUID { id }

    public static func newChild(id: UUID) -> RuleEntryModel {
        empty(id)
    }

    public static var empty: RuleEntryModel { empty(UUID()) }

    public static func empty(_ id: UUID) -> RuleEntryModel {
        RuleEntryModel(id: id, name: "", content: "")
    }

    public func duplicate() -> RuleEntryModel {
        duplicate(id: UUID(), parentId: parentId)
    }

    func duplicate(id: UUID, parentId: UUID?) -> RuleEntryModel {
        RuleEntryModel(
            id: id,
            name: name,
            content: content,
            kind: kind,
            displayState: displayState,
            parentId: parentId
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
            displayState: other.displayState,
            parentId: other.parentId
        )
    }

    public func isSame(_ other: RuleEntryModel) -> Bool {
        name == other.name &&
        content == other.content &&
        kind == other.kind &&
        parentId == other.parentId
    }
}

extension RuleEntryModel: ItemLinkEditable {
    public var textLinkContent: String {
        name.isEmpty ? content : "**\(name.trimmingCharacters(in: .whitespacesAndNewlines))**: \(content)"
    }
}


#if DEBUG
public extension RuleEntryModel {
    static func fixture(
        id: UUID = UUID(),
        name: String = "Rule section",
        content: String = "Rule content",
        kind: RuleEntryKind = .text,
        displayState: Int = 0,
        parentId: UUID? = nil
    ) -> RuleEntryModel {
        RuleEntryModel(
            id: id,
            name: name,
            content: content,
            kind: kind,
            displayState: displayState,
            parentId: parentId
        )
    }
}
#endif
