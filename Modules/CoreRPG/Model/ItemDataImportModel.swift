// @copyright André Trettin

import Foundation
import os.log
import Observation

@MainActor @Observable
public final class ItemDataImportModel: Sendable {
    public init(gameImporter: Bool = false) {
        self.gameImporter = gameImporter
    }

    public let gameImporter: Bool
    public var importedItems: Int = 0
    public var totalImportingItems: Int = 0
    public var isImportRunning: Bool = false
    public var withOverwrite: Bool = false
}

public enum ItemDataImportableError: Error {
    case openError
    case notEnoughData
    case unsupportedDataType
    case fileWithoutItem
    case cancel
}
