// @copyright André Trettin

import SwiftUI

struct FakeRootController: RootControllable {
    var exportControllable: any ExportControllable
    
    var importControllable: any ImportControllable
    
    var linkControllable: any LinkControllable
    
    var gameExportControllable: any ExportControllable
    
    var gameImportControllable: any ImportControllable
    
    @MainActor
    static let fake = FakeRootController(exportControllable: FakeExportController.fake, importControllable: FakeImportController.fake, linkControllable: FakeLinkController.fake, gameExportControllable: FakeExportController.fake, gameImportControllable: FakeImportController.fake)
}
