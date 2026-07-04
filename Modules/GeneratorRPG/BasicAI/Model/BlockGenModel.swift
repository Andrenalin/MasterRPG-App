// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels

@Generable(description: "The block can be of four category: Adventure, Map, Character or Table.")
public struct BlockGenModel: Equatable, Identifiable, Sendable {
    public let id: UUID = UUID()
    @Guide(description: "The name of this block.")
    public let name: String
    @Guide(description: "More information about the of this block. Usually a short summary or high level description.")
    public let information: String
    @Guide(description: "Tags to describe the content.")
    public let tags: [String]

    @Guide(description: "The block is from Type Adventure, Map, Character or Table.")
    public let blockCategory: BlockCategoryGenModel

    @Guide(description: "Each category has usually several smaller chunks.")
    public var entries: [BlockEntryGenModel]

    public var stableID: String {
        "\(blockCategory.rawValue)-\(name)-\(information)"
    }
}

@Generable()
public enum BlockCategoryGenModel: String, CaseIterable, Equatable, Sendable {
    case adventure
    case map
    case character
    case table
}

@Generable(description: "The entry of the block could be a section / chapter / paragraph")
public struct BlockEntryGenModel: Equatable, Identifiable, Sendable {
    public let id: UUID = UUID()
    @Guide(description: "A short title of this particular section, usually the section title.")
    public let title: String
    public let content: String

    public var stableID: String {
        "\(title)-\(content)"
    }
}

extension BlockEntryGenModel.PartiallyGenerated {
    var stableID: String {
        let value = [title, content]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return value.isEmpty ? "pending" : value
    }
}

#endif
