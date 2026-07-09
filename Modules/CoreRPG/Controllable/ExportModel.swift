// @copyright André Trettin

import Foundation
import Synchronization

// Holds the hub reference for ExportController. A class (not a struct field) so that
// every copy of an ExportController value — held independently by GameController,
// LinkController, ImportController, the root's own rootController, etc. — observes
// the same hubControllable once it's set, instead of each copy keeping its own snapshot.
public final class ExportModel: Sendable {
    public init() {}

    private let storage = Mutex<(any RootExportControllable)?>(nil)

    public var hubControllable: (any RootExportControllable)? {
        get {
            storage.withLock { $0 }
        }
        set {
            storage.withLock { $0 = newValue }
        }
    }
}
