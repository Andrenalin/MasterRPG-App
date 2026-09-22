// @copyright André Trettin

import Foundation
import os.log

/// Imports the shared example-adventure package (`exampleFirstData.gmz`)
/// used to build each module's `previewWithData` fixture.
///
/// This resource-lookup-result-check + import + await sequence was
/// duplicated verbatim across five modules' `PreviewData.swift` files,
/// differing only in the per-module follow-up run after the import
/// completes. See CODE_AUDIT_13 §9.4.
///
/// Takes the already-resolved `url` (rather than resolving
/// `RPGResources.Resources.exampleFirstData` itself) so this shared CoreRPG
/// helper doesn't need its own dependency on the `RPGResources` module —
/// every caller already imports it to build fixture data anyway.
public enum PreviewFixtureLoader {
    /// - Returns: `true` once the import has completed, `false` if `url` is
    ///   `nil` (nothing to await in that case — callers should skip their
    ///   own follow-up).
    @MainActor
    public static func importFirstExample(url: URL?, into importController: any ImportControllable) async -> Bool {
#if DEBUG
        guard let url else {
            Logger.bootStrap.debug("Preview fixture resource URL was nil")
            return false
        }
        let task = importController.importUrl(from: url)
        _ = try? await task.value
        return true
#else
        return false
#endif
    }
}
