// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import OSLog

/// Copies the files of audio items into the app's temporary track folder and loads them as
/// playlist items, a bounded number at a time. Knows nothing of the player or the playlist, so
/// the ordering and the concurrency bound can be tested on their own.
/// See CODE_AUDIT_Audio2 §9.15.
struct AudioTrackLoader: Sendable {
    /// Snapshot of the fields the @concurrent loading code needs, extracted on the
    /// MainActor so no live AudioModel instance crosses the isolation boundary.
    struct Request: Sendable {
        let id: UUID
        let title: String
        let subtitle: String
        let fileUrl: FileUrl
    }

    /// How many tracks are copied/loaded at the same time. Unbounded fan-out used to queue
    /// every track of a large playlist behind the file-coordination limiter at once.
    /// See CODE_AUDIT_18 §5.7.
    static let maxConcurrentLoads = 3

    let fileUrlDataController: FileUrlDataController?
    /// The extension of a track that has no file, only data.
    let filenameExtension: String

    /// The playlist items of `requests`, in request order; a request that could not be loaded
    /// (offline iCloud file, failed copy) has none.
    func load(_ requests: [Request]) async -> [PlaylistItem] {
        await Self.loadInOrder(requests, limit: Self.maxConcurrentLoads) { request in
            await self.audioAsset(for: request)
        }
    }

    /// Runs `load` for every element, at most `limit` at a time, and returns the results in the
    /// order of `elements`, without the elements that gave none.
    static func loadInOrder<Element: Sendable, Result: Sendable>(
        _ elements: [Element],
        limit: Int,
        load: @escaping @Sendable (Element) async -> Result?
    ) async -> [Result] {
        let loaded = await withTaskGroup(of: (Int, Result?).self) { group in
            var pending = elements.enumerated().makeIterator()
            for _ in 0..<max(1, limit) {
                guard let (index, element) = pending.next() else { break }
                group.addTask { (index, await load(element)) }
            }
            var results = [Int: Result?]()
            for await (index, result) in group {
                results[index] = result
                if let (nextIndex, nextElement) = pending.next() {
                    group.addTask { (nextIndex, await load(nextElement)) }
                }
            }
            return results
        }
        return elements.indices.compactMap { loaded[$0] ?? nil }
    }

    /// @concurrent: file copies and asset loading must not run on the main actor —
    /// nonisolated async would inherit the (main actor) caller's isolation here.
    @concurrent
    private func audioAsset(for request: Request) async -> PlaylistItem? {
        guard let fileUrlDataController else { return nil }

        var audioAsset: PlaylistItem? = nil
        do {
            audioAsset = try await fileUrlDataController.url(for: request.fileUrl) { url -> PlaylistItem? in
                guard let url else { return nil }
                // Read through the coordinated copy instead of the raw path: a coordinated
                // read of an evicted iCloud file waits for its download (CODE_AUDIT_17
                // §5.21), and works unchanged for local and app-group files. The former
                // explicit `startDownloadingUbiquitousItem` step took a coordinated *write*
                // lock, didn't wait, and could fail for non-ubiquitous files.
                // See CODE_AUDIT_18 §5.7.
                //
                // Copy file-to-file: AVURLAsset streams from disk, so the track never
                // needs to be loaded into memory.
                //
                // One temp file per load: two overlapping loads of the same track used to
                // share `<id>.<ext>`, so one could delete the file the other's asset was
                // still loading. Replacing/removing a playlist entry deletes its file, and
                // a discarded load deletes its own. See CODE_AUDIT_18 §3.7 (and §7.1).
                let tempUrl = Self.temporaryTrackUrl(for: request.id, pathExtension: url.pathExtension)
                try await FileManager.default.copyItem(coordinatingAccessFrom: url, to: tempUrl)
                return try await Self.loadingRemovingOnFailure(request, from: tempUrl)
            }
        } catch {
            Logger.audioController.error("Cannot read audio from file url: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }

        do {
            if audioAsset == nil, let data = request.fileUrl.data {
                let tempUrl = Self.temporaryTrackUrl(for: request.id, pathExtension: filenameExtension)
                try data.write(to: tempUrl)
                return try await Self.loadingRemovingOnFailure(request, from: tempUrl)
            }
        } catch {
            Logger.audioController.error("Cannot read audio from data: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
        return audioAsset
    }

    /// Loads the copied track, deleting the copy when loading fails: nothing else would ever
    /// remove it. See CODE_AUDIT_19 §7.3.
    private static func loadingRemovingOnFailure(_ request: Request, from tempUrl: URL) async throws -> PlaylistItem {
        do {
            return try await PlaylistItem.loading(id: request.id, title: request.title, subtitle: request.subtitle, from: tempUrl)
        } catch {
            try? FileManager.default.removeItem(at: tempUrl)
            throw error
        }
    }

    private static func temporaryTrackUrl(for id: UUID, pathExtension: String) -> URL {
        trackDirectory
            .appending(path: "\(id.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    /// The app's own folder for the temporary track copies. Emptied once per launch, on first
    /// use, before this run has created any copy: copies still present at the previous exit
    /// were never removed and piled up. See CODE_AUDIT_19 §7.3.
    private static let trackDirectory: URL = {
        let directory = URL.temporaryDirectory.appending(path: "AudioTracks", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Logger.audioController.error("Cannot create the audio track folder: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
        return directory
    }()
}
