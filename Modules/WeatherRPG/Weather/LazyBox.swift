// @copyright André Trettin

import Foundation

/// Holds a value that is built the first time it is read.
///
/// A view's `init` runs on every re-evaluation of its parent, and `State(initialValue:)` keeps
/// only the first value SwiftUI sees, so a heavy object passed there was built and thrown away
/// each time (one `StormDrop` per unit of rain strength while a slider was dragged). With a box,
/// the discarded copies cost one small allocation and never run `make`. See CODE_AUDIT_22 §8.1.
final class LazyBox<Value> {
    private let make: () -> Value
    private var stored: Value?

    init(_ make: @escaping () -> Value) {
        self.make = make
    }

    var value: Value {
        if let stored { return stored }
        let created = make()
        stored = created
        return created
    }
}
