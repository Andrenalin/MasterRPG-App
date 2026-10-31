// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG

@Suite("Sheet number limit")
struct SheetNumberLimitTests {
    private let limit = SheetNumberLimit.maximumMagnitude

    @Test("whole numbers are clamped to the magnitude")
    func clampsIntegers() {
        #expect(SheetNumberLimit.clamped(Int.max) == limit)
        #expect(SheetNumberLimit.clamped(Int.min) == -limit)
        #expect(SheetNumberLimit.clamped(42) == 42)
    }

    @Test("doubles never trap: NaN is 0 and infinity is the bound")
    func clampsDoubles() {
        #expect(SheetNumberLimit.clamped(Double.nan) == 0)
        #expect(SheetNumberLimit.clamped(Double.infinity) == limit)
        #expect(SheetNumberLimit.clamped(-1e300) == -limit)
        #expect(SheetNumberLimit.clamped(2.6) == 3)
    }

    @Test("a sum of two clamped numbers cannot overflow")
    func sumsWithoutOverflow() {
        #expect(SheetNumberLimit.sum(Int.max, Int.max) == limit)
        #expect(SheetNumberLimit.sum(-Int.max, -Int.max) == -limit)
        #expect(SheetNumberLimit.sum(5, -7) == -2)
    }
}
#endif
