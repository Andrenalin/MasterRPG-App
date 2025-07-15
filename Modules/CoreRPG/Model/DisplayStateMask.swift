// @copyright André Trettin

import Foundation

public enum DisplayStateMask: Int32 {
    case fullVisible = 0
    case groupHidden = 1
    case totalHidden = 2
    case nameHidden = 4
    case descriptionHidden = 8
    case otherHidden = 16

    public func set(on value: Int32) -> Int32 {
        value | rawValue
    }

    public func reset(on value: Int32) -> Int32 {
        value & ~rawValue
    }

    public func toggle(on value: Int32) -> Int32 {
        if value & rawValue == rawValue {
            return reset(on: value)
        } else {
            return set(on: value)
        }
    }
}
