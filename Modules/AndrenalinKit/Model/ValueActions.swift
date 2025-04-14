// @copyright André Trettin

import SwiftUI

public struct ValueActions {
    public init(addResult: @escaping (NetworkCodableDataType, UUID?) async -> Void, createModelResult: @escaping (String, String, [(String, String)], ResultCategory) -> NetworkCodableDataType, createEntryResult: @escaping (String, String, ResultCategory) -> NetworkCodableDataType) {
        self.addResult = addResult
        self.createModelResult = createModelResult
        self.createEntryResult = createEntryResult
    }

    public let addResult: (NetworkCodableDataType, UUID?) async -> Void

    public let createModelResult: (String, String, [(String, String)], ResultCategory) -> NetworkCodableDataType

    public let createEntryResult: (String, String, ResultCategory) -> NetworkCodableDataType
}

public extension EnvironmentValues {
    var valueActions: ValueActions {
        get { self[ValueActionsKey.self] }
        set { self[ValueActionsKey.self] = newValue }
    }
}

struct ValueActionsKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ValueActions = ValueActions { _, _ in } createModelResult: { _, _, _, _ in NetworkCodableDataType.empty } createEntryResult: { _, _, _ in NetworkCodableDataType.empty }
}
