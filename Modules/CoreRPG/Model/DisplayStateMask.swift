// @copyright André Trettin

import Foundation

public enum DisplayStateMask: Int {
    case fullVisible = 0
    case groupHidden = 1
    case totalHidden = 2
    case nameHidden = 4
    case descriptionHidden = 8
    case otherHidden = 16

    public func set(on value: Int) -> Int {
        value | rawValue
    }

    public func reset(on value: Int) -> Int {
        value & ~rawValue
    }

    public func toggle(on value: Int) -> Int {
        if value & rawValue == rawValue {
            return reset(on: value)
        } else {
            return set(on: value)
        }
    }
}
