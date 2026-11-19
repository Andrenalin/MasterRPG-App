// @copyright André Trettin

import Foundation

/// A value made on first access. `@State` holds the box, so the value is made once however often
/// the owning view's `init` runs.
@MainActor
final class QuickEditorLazyValue<Value> {
    private var make: (() -> Value)?
    private var stored: Value?

    init(_ make: @escaping () -> Value) {
        self.make = make
    }

    var value: Value {
        if let stored { return stored }
        let made = make?()
        make = nil
        guard let made else { preconditionFailure("The lazy value was read while it was being made.") }
        stored = made
        return made
    }
}
