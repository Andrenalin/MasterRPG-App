// @copyright André Trettin

import Foundation
import SwiftUI

/// Wrapper views that avoid AnyView type erasure while maintaining protocol flexibility
/// These views cache and optimize the view rendering from ViewControllable

/// Optimized wrapper for file importer views - eliminates AnyView overhead
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
