// @copyright André Trettin

import Foundation

@MainActor
public protocol RootControllable: Sendable {
    var exportControllable: any ExportControllable { get }
    var importControllable: any ImportControllable { get }
    var linkControllable: any LinkControllable { get }
    var gameExportControllable: any ExportControllable { get }
    var gameImportControllable: any ImportControllable { get }

}
