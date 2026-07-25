// @copyright André Trettin

import Foundation
import SwiftUI

public struct ItemGenerationSelection: Identifiable, Equatable, Hashable, Codable, Sendable {
    public init(
        id: UUID,
        tableId: UUID,
        tableName: String,
        entryId: UUID,
        entryName: String,
        content: String
    ) {
        self.id = id
        self.tableId = tableId
        self.tableName = tableName
        self.entryId = entryId
        self.entryName = entryName
        self.content = content
    }

    public let id: UUID
    public let tableId: UUID
    public let tableName: String
    public let entryId: UUID
    public let entryName: String
    public let content: String
}

public struct ItemGenerationSummary: Identifiable, Equatable, Hashable, Codable, Sendable {
    public init(
        id: UUID = UUID(),
        name: String,
        value: String,
        selections: [ItemGenerationSelection]
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.selections = selections
    }

    public let id: UUID
    public let name: String
    public let value: String
    public let selections: [ItemGenerationSelection]

    public func encodeData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decodeData(_ data: Data?) -> Self? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

public struct ItemGenerationAction: Sendable {
    public init(
        isEnabled: Bool = true,
        present: @MainActor @escaping @Sendable (UUID) -> Void
    ) {
        self.isEnabled = isEnabled
        self.present = present
    }

    public let isEnabled: Bool
    private let present: @MainActor @Sendable (UUID) -> Void

    @MainActor
    public func callAsFunction(_ itemId: UUID) {
        guard isEnabled else { return }
        present(itemId)
    }

    public static let disabled = ItemGenerationAction(isEnabled: false) { _ in }
}

public struct ItemGenerationResultAction: Sendable {
    public init(
        accept: @MainActor @escaping @Sendable (ItemGenerationSummary) -> Void
    ) {
        self.accept = accept
    }

    private let accept: @MainActor @Sendable (ItemGenerationSummary) -> Void

    @MainActor
    public func callAsFunction(_ summary: ItemGenerationSummary) {
        accept(summary)
    }

    public static let disabled = ItemGenerationResultAction { _ in }
}

public extension EnvironmentValues {
    @Entry var itemGenerationAction: ItemGenerationAction = .disabled
    @Entry var itemGenerationResultAction: ItemGenerationResultAction = .disabled
}

@MainActor
public protocol ItemGenerationControllable: Sendable {
    func generationView(
        itemId: UUID,
        dismissAction: @MainActor @escaping @Sendable () -> Void
    ) -> AnyView
}
