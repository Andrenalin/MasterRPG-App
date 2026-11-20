// @copyright André Trettin

import CoreRPG
import Foundation

extension FileUrlDataController {
    /// Resolves `fileUrl` through the standard three-step fallback — inline data, an in-place
    /// decode of the file, or (last resort) reading its bytes — and decodes the first one that
    /// succeeds. Consolidates a fallback chain that used to be
    /// duplicated across `CacheController.decodedImage`, `.downsampledSource`, and
    /// `PhotoRootModel.fetchPhotoThumbnailSource`. See CODE_AUDIT §9.6.
    /// `@concurrent`: the decode closures are synchronous ImageIO work that must not run on the
    /// caller's (usually main) actor. See CODE_AUDIT_16 §3.4.
    /// Runs at Default priority (`runAtDefaultPriority`), where ImageIO's own workers run, so a
    /// User-initiated caller does not wait on a lower-priority thread.
    @concurrent
    func resolvedImage<T: Sendable>(
        for fileUrl: FileUrl,
        decodeData: @escaping @Sendable (Data) -> T?,
        decodeUrl: @Sendable @escaping (URL) -> T?
    ) async -> T? {
        await runAtDefaultPriority {
            if let data = fileUrl.data {
                return decodeData(data)
            }
            // ImageIO reads a thumbnail or the pixel size straight from the file; loading all of a
            // 40 MB photo into memory first made every uncached thumbnail cost the whole file. The
            // bytes are only read when the file cannot be decoded in place (a placeholder that
            // still has to be downloaded, a remote copy). See CODE_AUDIT §7.3.
            if let decoded = await url(for: fileUrl, action: { url -> T? in
                guard let url else { return nil }
                return decodeUrl(url)
            }) {
                return decoded
            }
            if let data = try? await loadData(for: fileUrl) {
                return decodeData(data)
            }
            return nil
        }
    }
}
