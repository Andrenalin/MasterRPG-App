// @copyright André Trettin

import Combine
import SwiftUI

// Item models are MainActor-owned observable reference types. Diffing reads
// mutable CRDT/model state, so callers must enter the model's actor instead of
// relying on `MainActor.assumeIsolated` shims.
@MainActor
public protocol ItemDiffComparable {
    func isSame(_ other: Self) -> Bool
    func merge(_ other: Self) -> Self
    var version: Int { get }
}

public extension ItemDiffComparable {
    var version: Int {
        0
    }
}
