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

public struct ItemGenerationSummary: Identifiable, Equatable, Hashable, Codable, Sendable, MessageMapper {
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
}

public struct ItemGenerationAction: Sendable, Equatable {
    /// `id` should be stable across the writer's re-renders (e.g. the owning
    /// module) so SwiftUI's environment diffing can skip invalidating readers
    /// when the same writer re-supplies the same functional closure. `isEnabled`
    /// is compared separately since it's meaningful state that does need to be
    /// observed.
    public init(
        id: EnvironmentActionIdentity = .fresh(),
        isEnabled: Bool = true,
        present: @MainActor @escaping @Sendable (UUID) -> Void
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.present = present
    }

    let id: EnvironmentActionIdentity
    public let isEnabled: Bool
    private let present: @MainActor @Sendable (UUID) -> Void

    @MainActor
    public func callAsFunction(_ itemId: UUID) {
        guard isEnabled else { return }
        present(itemId)
    }

    public static let disabled = ItemGenerationAction(isEnabled: false) { _ in }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.isEnabled == rhs.isEnabled
    }
}

public struct ItemGenerationResultAction: Sendable, Equatable {
    /// `id` should be stable across the writer's re-renders (e.g. the owning
    /// root model's `ObjectIdentifier`) so SwiftUI's environment diffing can
    /// skip invalidating readers when the same root writes the same
    /// functional closure again.
    public init(
        id: EnvironmentActionIdentity = .fresh(),
        accept: @MainActor @escaping @Sendable (ItemGenerationSummary) -> Void
    ) {
        self.id = id
        self.accept = accept
    }

    let id: EnvironmentActionIdentity
    private let accept: @MainActor @Sendable (ItemGenerationSummary) -> Void

    @MainActor
    public func callAsFunction(_ summary: ItemGenerationSummary) {
        accept(summary)
    }

    public static let disabled = ItemGenerationResultAction { _ in }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
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
