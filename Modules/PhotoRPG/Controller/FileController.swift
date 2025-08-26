// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

struct FileController: Sendable {
    static var fileTypes: [UTType] { [.image] }
    static var filenameExtension: String { "jpg" }
    
    private var _fileUrlDataController: FileUrlDataController?
    
    var fileUrlDataController: FileUrlDataController {
        _fileUrlDataController.unsafelyUnwrapped
    }
    
    @MainActor
    init() {
        _fileUrlDataController = FileUrlDataController(moduleFolder: NetworkModules.photo.token, fileTypes: FileController.fileTypes, filenameExtension: FileController.filenameExtension)
    }
}
