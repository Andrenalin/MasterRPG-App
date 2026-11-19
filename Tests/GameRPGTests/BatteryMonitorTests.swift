// @copyright André Trettin

#if os(iOS) && canImport(Testing)
import Foundation
import Testing
import UIKit

@testable import GameRPG

/// CODE_AUDIT_TestGaps §8.5: the battery monitor of the game toolbar. Battery monitoring is
/// process-wide, so it has to stay on until the last monitor stops, and a monitor that is only
/// created (a `@State` initial value rebuilt by every parent update) must observe nothing.
@MainActor
@Suite("Battery monitor", .serialized)
struct BatteryMonitorTests {
    @Test("A new monitor starts with nothing to show and does not start monitoring")
    func creationHasNoSideEffects() {
        let before = BatteryMonitor.activeMonitorCount

        let monitor = BatteryMonitor()

        #expect(monitor.status == .unavailable)
        #expect(BatteryMonitor.activeMonitorCount == before)
    }

    @Test("Monitoring stays on until the last of two monitors stops")
    func monitoringIsSharedBetweenMonitors() {
        let baseline = BatteryMonitor.activeMonitorCount
        let first = BatteryMonitor()
        let second = BatteryMonitor()

        first.startMonitoring()
        second.startMonitoring()
        #expect(BatteryMonitor.activeMonitorCount == baseline + 2)

        first.stopMonitoring()
        #expect(BatteryMonitor.activeMonitorCount == baseline + 1, "the second monitor still needs monitoring")

        second.stopMonitoring()
        #expect(BatteryMonitor.activeMonitorCount == baseline)
    }

    @Test("Starting twice and stopping twice is balanced")
    func startAndStopAreIdempotent() {
        let baseline = BatteryMonitor.activeMonitorCount
        let monitor = BatteryMonitor()
        let other = BatteryMonitor()
        other.startMonitoring()

        monitor.startMonitoring()
        monitor.startMonitoring()
        #expect(BatteryMonitor.activeMonitorCount == baseline + 2, "a second start of one monitor counts once")
        monitor.stopMonitoring()
        monitor.stopMonitoring()

        #expect(BatteryMonitor.activeMonitorCount == baseline + 1, "a doubled stop must not end the other monitor's access")
        other.stopMonitoring()
        #expect(BatteryMonitor.activeMonitorCount == baseline)
    }

    @Test("Stopping a monitor that never started changes nothing")
    func stopWithoutStart() {
        let baseline = BatteryMonitor.activeMonitorCount
        let running = BatteryMonitor()
        running.startMonitoring()

        BatteryMonitor().stopMonitoring()

        #expect(BatteryMonitor.activeMonitorCount == baseline + 1)
        running.stopMonitoring()
        #expect(BatteryMonitor.activeMonitorCount == baseline)
    }

    @Test("A monitor that is charging or has no reading shows nothing")
    func nonDischargingStatesShowNothing() {
        let monitor = BatteryMonitor()
        monitor.startMonitoring()
        defer { monitor.stopMonitoring() }

        // The simulator reports an unknown battery, never an unplugged one with a level.
        if UIDevice.current.batteryState != .unplugged {
            #expect(monitor.status == .unavailable)
        } else if case .onBattery(let level) = monitor.status {
            #expect((0...1).contains(level))
        }
    }
}
#endif
