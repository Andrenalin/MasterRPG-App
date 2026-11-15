// @copyright André Trettin

import Foundation

/// What is left of earlier scans in the capture folder, and what may go. Separate from
/// `CaptureFolderManager` (which only builds for a device) so the decision can be tested on the
/// simulator. See CODE_AUDIT_26 §10.20.
enum ScanFolderCleanup {
    static let rawPhotoFolderNames = ["Images", "Snapshots"]

    /// Removes the leftovers of earlier scans below `capturesFolder`. Only folders created before
    /// `cutoff` are touched, so the folder of a capture started meanwhile stays. A scan with
    /// model files keeps its Models folder (it can be the only copy of a model that could not be
    /// attached), and only its raw photos go.
    nonisolated static func removeStaleScans(in capturesFolder: URL, createdBefore cutoff: Date) {
        guard let staleFolders = try? FileManager.default.contentsOfDirectory(
            at: capturesFolder,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        for folder in staleFolders {
            if let created = try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate,
               created >= cutoff {
                continue
            }
            if hasModelFiles(in: folder) {
                for name in rawPhotoFolderNames {
                    try? FileManager.default.removeItem(at: folder.appending(path: name, directoryHint: .isDirectory))
                }
                continue
            }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Whether the scan folder holds any model file (hidden files do not count).
    nonisolated static func hasModelFiles(in scanFolder: URL) -> Bool {
        let modelsFolder = scanFolder.appending(path: "Models", directoryHint: .isDirectory)
        let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents?.isEmpty == false
    }
}
