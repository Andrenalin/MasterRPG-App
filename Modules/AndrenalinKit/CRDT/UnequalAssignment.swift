// @copyright André Trettin

import Foundation

infix operator <=>: AssignmentPrecedence

public func <=> <T: Equatable>(lhs: inout T, rhs: T) {
    if lhs != rhs {
        lhs = rhs
    }
}

public func unequalSet<T: Equatable>(lhs: inout T, rhs: T, apply: @escaping () -> Void) {
    if lhs != rhs {
        lhs = rhs
        apply()
    } else {
        apply()
    }
}
