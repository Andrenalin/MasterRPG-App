/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A class that supports the creation, listing, and filename support of a capture folder.
*/

#if os(iOS) && !targetEnvironment(simulator)

import CoreRPG
import Dispatch
import Foundation
import os

@MainActor @Observable
final class CaptureFolderManager {
    // The top-level capture directory that contains Images and Snapshots subdirectories.
    // This sample automatically creates this directory at `init()` with timestamp.
    let rootScanFolder: URL

    // Subdirectory of `rootScanFolder` for images
    let imagesFolder: URL

    // Subdirectory of `rootScanFolder` for snapshots
    let snapshotsFolder: URL

    // Subdirectory to output model files.
    let modelsFolder: URL

    var shots: [ShotFileInfo] = []

    init?() {
        guard let newFolder = CaptureFolderManager.createNewScanDirectory() else {
            Logger.scanner3D.error("Unable to create a new scan directory.")
            return nil
        }
        rootScanFolder = newFolder

        // Creates the subdirectories.
        imagesFolder = newFolder.appending(path: "Images/")
        guard CaptureFolderManager.createDirectoryRecursively(imagesFolder) else {
            return nil
        }

        snapshotsFolder = newFolder.appending(path: "Snapshots/")
        guard CaptureFolderManager.createDirectoryRecursively(snapshotsFolder) else {
            return nil
        }

        modelsFolder = newFolder.appending(path: "Models/")
        guard CaptureFolderManager.createDirectoryRecursively(modelsFolder) else {
            return nil
        }
    }

    func loadShots() async throws {
        Logger.scanner3D.debug("Loading snapshots (async)...")

        var newShots: [ShotFileInfo] = []

        let imgUrls = try FileManager.default
            .contentsOfDirectory(at: imagesFolder,
                                 includingPropertiesForKeys: [],
                                 options: [.skipsHiddenFiles])
            .filter { $0.isFileURL
                && $0.lastPathComponent.hasSuffix(CaptureFolderManager.heicImageExtension)
            }
        for imgUrl in imgUrls {
            guard let shotFileInfo = ShotFileInfo(url: imgUrl) else {
                Logger.scanner3D.error("Can't get shotId from url: \"\(imgUrl)\")")
                continue
            }

            newShots.append(shotFileInfo)
        }

        // Sorts and then makes the final replacement in the published array.
        newShots.sort(by: { $0.id < $1.id })
        shots = newShots
    }

    /// Retrieves the image id from of an existing file at a URL.\
    ///
    /// - Parameter url: URL of the photo for which this method returns the image id.
    /// - Returns: The image ID if `url` is valid; otherwise `nil`.
    static func parseShotId(url: URL) -> UInt32? {
        let photoBasename = url.deletingPathExtension().lastPathComponent
        Logger.scanner3D.debug("photoBasename = \(photoBasename)")

        guard let endOfPrefix = photoBasename.lastIndex(of: "_") else {
            Logger.scanner3D.warning("Can't get endOfPrefix!")
            return nil
        }

        let imgPrefix = photoBasename[...endOfPrefix]
        guard imgPrefix == imageStringPrefix else {
            Logger.scanner3D.warning("Prefix doesn't match!")
            return nil
        }

        let idString = photoBasename[photoBasename.index(after: endOfPrefix)...]
        guard let id = UInt32(idString) else {
            Logger.scanner3D.warning("Can't convert idString=\"\(idString)\" to uint32!")
            return nil
        }

        return id
    }

    /// Creates a new Scans directory based on the current timestamp in the top level Documents
    /// folder.
    /// - Returns: The new Scans folder's file URL, or `nil` on error.
    static func createNewScanDirectory() -> URL? {
        guard let capturesFolder = rootScansFolder() else {
            Logger.scanner3D.error("Can't get user document dir!")
            return nil
        }

        let timestamp = Date().formatted(.iso8601)
        let newCaptureDir = capturesFolder
            .appending(path: timestamp, directoryHint: .isDirectory)

        Logger.scanner3D.log("Creating capture path: \"\(String(describing: newCaptureDir))\"")
        let capturePath = newCaptureDir.path(percentEncoded: false)
        do {
            try FileManager.default.createDirectory(atPath: capturePath,
                                                    withIntermediateDirectories: true)
        } catch {
            Logger.scanner3D.error("Failed to create capturepath=\"\(capturePath)\" error=\(String(describing: error))")
            return nil
        }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: capturePath, isDirectory: &isDir)
        guard exists && isDir.boolValue else {
            return nil
        }

        return newCaptureDir
    }

    // - MARK: Private interface below.

    /// Creates all path components for the output directory.
    /// - Parameter outputDir: A URL for the new output directory.
    /// - Returns: A Boolean value that indicates whether the method succeeds,
    /// otherwise `false` if it encounters an error, such as if the file already
    /// exists or the method couldn't create the file.
    private static func createDirectoryRecursively(_ outputDir: URL) -> Bool {
        guard outputDir.isFileURL else {
            return false
        }
        let expandedPath = outputDir.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        let fileManager = FileManager()
        guard !fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory) else {
            Logger.scanner3D.error("File already exists at \(expandedPath, privacy: .private)")
            return false
        }

        Logger.scanner3D.log("Creating dir recursively: \"\(expandedPath, privacy: .private)\"")

        let result: ()? = try? fileManager.createDirectory(atPath: expandedPath,
                                                           withIntermediateDirectories: true)

        guard result != nil else {
            return false
        }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDir) && isDir.boolValue else {
            Logger.scanner3D.error("Dir \"\(expandedPath, privacy: .private)\" doesn't exist after creation!")
            return false
        }

        Logger.scanner3D.log("... success creating dir.")
        return true
    }

    // Constants this sample appends in front of the capture id to get a file basename.
    private static let imageStringPrefix = "IMG_"
    private static let heicImageExtension = "HEIC"

    /// Returns the folder for all in-progress captures.
    ///
    /// Deliberately under `URL.cachesDirectory`, not `URL.documentsDirectory`: raw capture
    /// photos of a user's real tabletop/miniatures/room shouldn't be Finder/Files-app
    /// visible (this app has `UIFileSharingEnabled`) or included in iCloud/device backups
    /// for the whole capture+reconstruction lifetime. See CODE_AUDIT_Space §6.1.
    private nonisolated static func rootScansFolder() -> URL? {
        URL.cachesDirectory.appending(path: "Scans/", directoryHint: .isDirectory)
    }

    /// Deletes any `Scans/*` subfolders left behind by a crash or force-quit during a
    /// previous run. Call once, early, before a new capture folder is created — there's no
    /// other reachable teardown point for a session that never reached `reset()`.
    /// See CODE_AUDIT_Space §6.1.
    ///
    /// Safe to run off the main actor and concurrently with a new capture: only folders created
    /// before `cutoff` (the moment the app asked for the cleanup) are touched, so the folder of a
    /// capture started meanwhile is never deleted. See CODE_AUDIT_26 §7.65.
    nonisolated static func cleanupStaleScans(createdBefore cutoff: Date = .now) {
        guard let capturesFolder = rootScansFolder() else { return }
        guard let staleFolders = try? FileManager.default.contentsOfDirectory(
            at: capturesFolder,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        for folder in staleFolders {
            if let created = try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate,
               created >= cutoff {
                continue
            }
            // A scan whose model could not be attached keeps its Models folder (see
            // `AppDataModel.reset()`): it is the only copy, so only the raw photos go.
            if hasModelFiles(in: folder) {
                for name in ["Images", "Snapshots"] {
                    try? FileManager.default.removeItem(at: folder.appending(path: name, directoryHint: .isDirectory))
                }
                continue
            }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private nonisolated static func hasModelFiles(in scanFolder: URL) -> Bool {
        let modelsFolder = scanFolder.appending(path: "Models", directoryHint: .isDirectory)
        let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents?.isEmpty == false
    }
}

#endif
