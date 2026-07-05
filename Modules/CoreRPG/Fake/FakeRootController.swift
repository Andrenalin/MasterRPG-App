// @copyright André Trettin

import SwiftUI

struct FakeRootController: RootExportControllable {
    var exportControllable: any ExportControllable

    var importControllable: any ImportControllable

    @MainActor
    static let fake: FakeRootController = {
        let root = FakeRootController(exportControllable: FakeExportController.fake, importControllable: FakeImportController.fake)
        FakeExportController.fake.hubControllable = root
        return root
    }()
}
