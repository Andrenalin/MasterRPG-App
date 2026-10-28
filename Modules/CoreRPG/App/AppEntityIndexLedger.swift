// @copyright André Trettin

import Foundation
import os.log

/// The ids each module's App Entity index already covers, kept across launches. A launch loads
/// every item without a change, so the reindex compares the loaded ids with this list: only the ids
/// that are new (added while the app was not running, e.g. by the share extension) or gone are
/// looked at, plus the ones the item controller marked as changed. Without it every launch indexed
/// every item of every module. No list for a module means its first run, which covers every item.
/// See CODE_AUDIT_Since_3.0.1 §3.1.
@MainActor
public final class AppEntityIndexLedger {
    public static let shared = AppEntityIndexLedger(
        directory: .applicationSupportDirectory.appending(path: "AppEntityIndex", directoryHint: .isDirectory)
    )

    private let directory: URL
    /// What was read or written per module token; an entry holding `nil` means no list exists.
    private var cache: [String: Set<UUID>?] = [:]

    public init(directory: URL) {
        self.directory = directory
    }

    /// The ids the module's index covers, or `nil` before its first complete run.
    public func indexedIds(for token: String) async -> Set<UUID>? {
        if let cached = cache[token] {
            return cached
        }
        let url = fileUrl(for: token)
        // A list that can't be read counts as missing: the next run covers every item again.
        let ids: Set<UUID>? = try? await runOffCallerExecutor { () throws -> Set<UUID>? in
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            return try JSONDecoder().decode(Set<UUID>.self, from: Data(contentsOf: url))
        }
        cache[token] = .some(ids)
        return ids
    }

    public func setIndexedIds(_ ids: Set<UUID>, for token: String) async {
        guard cache[token] != .some(ids) else { return }
        cache[token] = .some(ids)
        let url = fileUrl(for: token)
        let directory = directory
        do {
            try await runOffCallerExecutor {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(ids).write(to: url, options: .atomic)
            }
        } catch {
            // The next launch then treats the ids as new and indexes them again; nothing is lost.
            Logger.appIntents.error("Writing the \(token, privacy: .public) App Entity index list failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }

    private func fileUrl(for token: String) -> URL {
        directory.appending(path: "\(token).json")
    }
}

/// The decisions of one App Entity reindex pass, kept free of Core Spotlight so they can be tested.
public enum AppEntityIndexPass {
    /// The ids a pass looks at: everything on the first run (`indexed` is `nil`), afterwards the
    /// marked ones plus the ids that were added or removed since the index last covered them.
    public static func ids(current: Set<UUID>, changed: Set<UUID>, indexed: Set<UUID>?) -> Set<UUID> {
        guard let indexed else { return current.union(changed) }
        return changed
            .union(current.subtracting(indexed))
            .union(indexed.subtracting(current))
    }

    /// What the index covers after a pass over `looked` that failed for `failed`: the ids that still
    /// exist and were looked at now or before. Failed ids stay out, so the next launch retries them
    /// even though the marks of this run are gone by then.
    public static func indexed(
        before indexed: Set<UUID>?,
        looked: Set<UUID>,
        failed: Set<UUID>,
        current: Set<UUID>
    ) -> Set<UUID> {
        (indexed ?? []).union(looked).intersection(current).subtracting(failed)
    }
}
