// @copyright André Trettin

import Foundation

/// Holds the generation model of `TableGenerationRootView`, made on the first read: `@State` keeps
/// the first box only, so the model is not rebuilt on every parent update.
/// See CODE_AUDIT_TestGaps §8.5.
@MainActor
final class LazyGenerationModel {
    private var model: TableGenerationModel?

    func model(_ make: () -> TableGenerationModel) -> TableGenerationModel {
        if let model { return model }
        let made = make()
        model = made
        return made
    }
}
