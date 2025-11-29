// @copyright André Trettin

import SwiftUI

struct FakeRootController: RootControllable {
    var exportControllable: any ExportControllable
    
    var importControllable: any ImportControllable
    
    var linkControllable: any LinkControllable
    
    var linkRegisterControllable: any LinkRegisterControllable
    
    var gameExportControllable: any ExportControllable
    
    var gameImportControllable: any ImportControllable
    
    @MainActor
    static let fake = FakeRootController(exportControllable: FakeExportController.fake, importControllable: FakeImportController.fake, linkControllable: FakeLinkController.fake, linkRegisterControllable: FakeLinkRegisterController.fake, gameExportControllable: FakeExportController.fake, gameImportControllable: FakeImportController.fake)
}
