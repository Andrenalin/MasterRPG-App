// @copyright André Trettin

import Foundation
import os.log
import Observation

@MainActor @Observable
public final class ItemDataExportModel: Sendable {
    public init(gameExporter: Bool = false) {
        self.gameExporter = gameExporter
    }

    public let gameExporter: Bool
    public var exportedItems: Int = 0
    public var totalExportingItems: Int = 0
    public var isExportRunning: Bool = false
}

public enum ItemDataExportableError: Error {
    case openError
    case streamError
    case writeError
}

enum ExportDataToken: Int {
    case version_2024 = 1
    case counter = 8_096
    case item = 10_000
    case file = 10_001
}

struct GmzFileHeader {
    let counter: Int
    let token: Int
    let version: Int
}
