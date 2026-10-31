// @copyright André Trettin

import Foundation
import os.log

public extension Logger {
    static let subsystem = Bundle.main.bundleIdentifier!

    static let appIntents = Logger(subsystem: subsystem, category: "AppIntents")
    static let bootStrap = Logger(subsystem: subsystem, category: "BootStrap")
    static let bookmarkStore = Logger(subsystem: subsystem, category: "BookmarkController")
    static let cacheController = Logger(subsystem: subsystem, category: "CacheController")
    static let codable = Logger(subsystem: subsystem, category: "Codable")
    static let editController = Logger(subsystem: subsystem, category: "EditController")
    static let exportController = Logger(subsystem: subsystem, category: "ExportController")
    static let fileStore = Logger(subsystem: subsystem, category: "FileStore")
    static let folderListControllable = Logger(subsystem: subsystem, category: "FolderListControllable")
    static let gameController = Logger(subsystem: subsystem, category: "GameController")
    static let generatorRPG = Logger(subsystem: subsystem, category: "GeneratorRPG")
    static let importController = Logger(subsystem: subsystem, category: "ImportController")
    static let itemController = Logger(subsystem: subsystem, category: "ItemController")
    static let linkController = Logger(subsystem: subsystem, category: "LinkController")
    static let navigation = Logger(subsystem: subsystem, category: "Navigation")
    static internal let persistenceController = Logger(subsystem: subsystem, category: "PersistenceController")
    static internal let persistentHistory = Logger(subsystem: subsystem, category: "PersistentHistory")
    static let networking = Logger(subsystem: subsystem, category: "networking")
    static let scenesManager = Logger(subsystem: subsystem, category: "ScenesManager")
    static let sheetController = Logger(subsystem: subsystem, category: "SheetController")
    static let sharePlay = Logger(subsystem: subsystem, category: "sharePlay")
    static let syncDataControllable = Logger(subsystem: subsystem, category: "SyncDataControllable")
    static let tipKit = Logger(subsystem: subsystem, category: "TipKit")
    static let validateRepair = Logger(subsystem: subsystem, category: "ValidateRepair")
    static let widget = Logger(subsystem: subsystem, category: "widget")
}
