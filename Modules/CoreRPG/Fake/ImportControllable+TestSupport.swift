// @copyright André Trettin

import Foundation

/// Test-only convenience, kept with the other fakes and fixtures instead of the import code.
/// See CODE_AUDIT_Folder §9.1.
extension ImportControllable {
    /// Imports a stream with a fresh merge-mode model and no progress tracking.
    func importStream(from inputStream: InputStream, forceSave: Bool) async throws {
        let importModel = await ItemDataImportModel()
        try await importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
    }
}
