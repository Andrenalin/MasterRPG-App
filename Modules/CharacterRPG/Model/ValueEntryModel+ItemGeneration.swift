// @copyright André Trettin

import CoreRPG
import Foundation

public extension ValueEntryModel {
    init(generationSummary: ItemGenerationSummary) {
        self.init(
            id: generationSummary.id,
            name: generationSummary.name,
            type: .text,
            isGenerator: true,
            value: generationSummary.value
        )
    }
}
