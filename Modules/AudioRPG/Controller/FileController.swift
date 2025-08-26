// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

struct FileController: Sendable {
    static var fileTypes: [UTType] { [.audio] }
    static var filenameExtension: String { "m4a" }

    private var _fileUrlDataController: FileUrlDataController?
    
    var fileUrlDataController: FileUrlDataController {
        _fileUrlDataController.unsafelyUnwrapped
    }
    
    @MainActor
    init() {
        _fileUrlDataController = FileUrlDataController(moduleFolder: NetworkModules.audio.token, fileTypes: FileController.fileTypes, filenameExtension: FileController.filenameExtension)
    }
}
