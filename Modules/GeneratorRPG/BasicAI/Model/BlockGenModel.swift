// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels

@Generable(description: "The entry of the block could be a section / chapter / paragraph")
public struct BlockEntryGenModel: Identifiable, Sendable {
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

// Declared in an extension: the `@Generable` macro copies a conformance listed on the struct to
// `PartiallyGenerated`, which a custom `==` cannot satisfy.
extension BlockEntryGenModel: Equatable {
    /// Two entries with the same text are equal; the random `id` only identifies the instance.
    /// See CODE_AUDIT_26 §5.118.
    public static func == (lhs: BlockEntryGenModel, rhs: BlockEntryGenModel) -> Bool {
        lhs.title == rhs.title && lhs.content == rhs.content
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
