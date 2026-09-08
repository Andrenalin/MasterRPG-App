// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels

@Generable(description: "The entry of the block could be a section / chapter / paragraph")
public struct BlockEntryGenModel: Equatable, Identifiable, Sendable {
    public let id: UUID = UUID()
    @Guide(description: "A short title of this particular section, usually the section title.")
    public let title: String
    public let content: String

    public var stableId: String {
        "\(title)-\(content)"
    }

    public init(title: String, content: String) {
        self.title = title
        self.content = content
    }
}

extension BlockEntryGenModel.PartiallyGenerated {
    var stableId: String {
        let value = [title, content]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return value.isEmpty ? "pending" : value
    }
}

#endif
