// @copyright André Trettin

import Foundation

// Holds the hub reference for ExportController. A class (not a struct field) so that
// every copy of an ExportController value — held independently by GameController,
// LinkController, ImportController, the root's own rootController, etc. — observes
// the same hubControllable once it's set, instead of each copy keeping its own snapshot.
public final class ExportModel: @unchecked Sendable {
    public init() {}
    public var hubControllable: (any RootExportControllable)?
}
