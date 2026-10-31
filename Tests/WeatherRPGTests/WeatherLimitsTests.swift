// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import WeatherRPG

@Suite("Weather limits")
struct WeatherLimitsTests {
    @Test("values outside the slider range are clamped, NaN takes the lower bound")
    func clamps() {
        #expect(WeatherLimits.clamped(.nan, to: WeatherLimits.rainIntensity) == 0)
        #expect(WeatherLimits.clamped(1e300, to: WeatherLimits.rainIntensity) == 1000)
        #expect(WeatherLimits.clamped(-5, to: WeatherLimits.rainAngle) == -5)
        #expect(WeatherLimits.clamped(-500, to: WeatherLimits.rainAngle) == -90)
    }

    @Test("animation counts are whole numbers inside the range")
    func counts() {
        #expect(WeatherLimits.count(.infinity, in: WeatherLimits.lightningMaxBolts) == 10)
        #expect(WeatherLimits.count(-1, in: WeatherLimits.lightningMaxBolts) == 0)
    }
}
#endif
