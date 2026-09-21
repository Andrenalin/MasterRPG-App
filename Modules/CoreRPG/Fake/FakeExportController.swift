// @copyright André Trettin

import Foundation
import SwiftUI
import Synchronization

/// Preview/test double. The hub is late-bound after setup, so it lives behind a lock instead
/// of an unsynchronized `var` on an `@unchecked Sendable` class. See CODE_AUDIT_16 §3.18.
final class FakeExportController: ExportControllable, Sendable {
    init(itemControllable: any ItemControllable, hubControllable: (any RootExportControllable)? = nil) {
        self.itemControllable = itemControllable
        self.hub = Mutex(hubControllable)
    }

    let itemControllable: any ItemControllable
    private let hub: Mutex<(any RootExportControllable)?>
    var hubControllable: any RootExportControllable {
        get {
            guard let hub = hub.withLock({ $0 }) else {
                preconditionFailure("\(itemControllable.config.module.token) export requires its Adventure export hub after setup.")
            }
            return hub
        }
        set { hub.withLock { $0 = newValue } }
    }

    @MainActor static let fake: FakeExportController = {
        FakeExportController(itemControllable: FakeItemController.fake)
    }()
}
