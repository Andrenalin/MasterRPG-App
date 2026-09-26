// @copyright André Trettin

import Foundation

/// An element paired with how many equal elements came before it, so a `ForEach` over values
/// that can repeat (tags, AI-generated entries) gets unique ids: the n-th "Dagger" is always
/// `("Dagger", n)`. Unlike an offset, the id doesn't change when distinct values reorder.
/// See CODE_AUDIT_18 §8.4.
public struct OccurrenceKeyed<Element: Hashable>: Hashable, Identifiable {
    public let element: Element
    public let occurrence: Int

    public var id: Self { self }
}

public extension Sequence where Element: Hashable {
    func occurrenceKeyed() -> [OccurrenceKeyed<Element>] {
        var seen: [Element: Int] = [:]
        return map { element in
            let occurrence = seen[element, default: 0]
            seen[element] = occurrence + 1
            return OccurrenceKeyed(element: element, occurrence: occurrence)
        }
    }
}
