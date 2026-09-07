// @copyright André Trettin

import Foundation
import SwiftUI

/// Wrapper views that avoid dispatching through `any ViewControllable` existentials while
/// maintaining protocol flexibility. `ViewControllable.fileImporterView(...)` still returns
/// `AnyView` (a protocol requirement can't return `some View`), so this wrapper only avoids the
/// existential-dispatch overhead of calling through `any ViewControllable` directly — it does
/// not eliminate the `AnyView` boxing itself. See CODE_AUDIT §8.5.

/// Generic wrapper for a concrete `Controller: ViewControllable` — avoids `any ViewControllable`
/// existential dispatch when the concrete type is statically known.
public struct FileImporterViewWrapper<Controller: ViewControllable>: View {
    let controller: Controller
    let itemId: UUID
    let preopen: Bool
    let layoutDown: Bool

    public init(controller: Controller, itemId: UUID, preopen: Bool, layoutDown: Bool) {
        self.controller = controller
        self.itemId = itemId
        self.preopen = preopen
        self.layoutDown = layoutDown
    }

    public var body: some View {
        controller.fileImporterView(for: itemId, preopen: preopen, layoutDown: layoutDown)
    }
}

#Preview("File Importer Wrapper") {
    FileImporterViewWrapper(controller: FakeViewController(), itemId: .fixture1, preopen: false, layoutDown: false)
}
