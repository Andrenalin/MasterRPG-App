// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

struct FileController: Sendable {
    static var fileTypes: [UTType] { [.usdz] }
    static var filenameExtension: String { "usdz" }
    
    private var _fileUrlDataController: FileUrlDataController?
    
    var fileUrlDataController: FileUrlDataController {
        _fileUrlDataController.unsafelyUnwrapped
    }
    
    @MainActor
    init() {
        _fileUrlDataController = FileUrlDataController(moduleFolder: NetworkModules.space.token, fileTypes: FileController.fileTypes, filenameExtension: FileController.filenameExtension)
    }
}
