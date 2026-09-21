// @copyright André Trettin

import CoreRPG
import Foundation

extension FileUrlDataController {
    /// Resolves `fileUrl`'s bytes through the standard three-step fallback — inline
    /// data, a downloaded copy, or (last resort) a direct file read — and decodes
    /// the first one that succeeds. Consolidates a fallback chain that used to be
    /// duplicated across `CacheController.decodedImage`, `.downsampledSource`, and
    /// `PhotoRootModel.fetchPhotoThumbnailSource`. See CODE_AUDIT §9.6.
    /// `@concurrent`: the decode closures are synchronous ImageIO work that must not run on the
    /// caller's (usually main) actor. See CODE_AUDIT_16 §3.4.
    @concurrent
    func resolvedImage<T: Sendable>(
        for fileUrl: FileUrl,
        decodeData: @Sendable (Data) -> T?,
        decodeUrl: @Sendable @escaping (URL) -> T?
    ) async -> T? {
        if let data = fileUrl.data {
            return decodeData(data)
        } else if let data = try? await loadData(for: fileUrl) {
            return decodeData(data)
        } else {
            return await url(for: fileUrl) { url -> T? in
                guard let url else { return nil }
                return decodeUrl(url)
            }
        }
    }
}
