// @copyright André Trettin

import CoreRPG
import Foundation

/// Holds the viewport model of `ImageViewer`, created on the first read: `@State` keeps the first
/// box only, so the model is not rebuilt (and the image measured again) on every parent render.
/// See CODE_AUDIT_20 §7.3 and CODE_AUDIT_TestGaps §8.5.
@MainActor
final class ViewportModelStore {
    private var stored: ViewportModel?

    /// The model made by the first call; later calls return it without calling `make`.
    func model(_ make: () -> ViewportModel) -> ViewportModel {
        if let stored { return stored }
        let made = make()
        stored = made
        return made
    }

    var hasModel: Bool { stored != nil }
}
