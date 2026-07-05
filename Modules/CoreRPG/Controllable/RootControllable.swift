// @copyright André Trettin

import Foundation

// Narrow surface for reaching the Adventure hub's export/import from a leaf module,
// without pulling in concerns that leaf modules never use.
@MainActor
public protocol RootExportControllable: Sendable {
    var exportControllable: any ExportControllable { get }
    var importControllable: any ImportControllable { get }
}
