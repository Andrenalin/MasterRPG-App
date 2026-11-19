// @copyright André Trettin

import Foundation
import Observation

#if os(iOS) || os(visionOS)
import UIKit
#endif
#if os(macOS)
import IOKit.ps
#endif

/// Watches the system battery, where available, and reduces it to the one
/// state this view cares about: the discharging level, or nothing to show.
/// Charging, full, and platforms without a queryable battery (tvOS, most
/// Macs) all collapse to `.unavailable` so the icon disappears rather than
/// showing a stale or meaningless reading.
@MainActor
@Observable
final class BatteryMonitor {
    /// Does not start monitoring: `BatteryView` creates this in its `@State` initial value, which
    /// runs on every re-evaluation of the parent although SwiftUI keeps only the first instance.
    /// A monitor that started here left observers (or, on macOS, an endless poll) behind for
    /// each discarded one. The view starts the kept instance in `onAppear`. See CODE_AUDIT_22 §3.1.
    init() {}

    enum Status: Equatable, Sendable {
        case unavailable
        case onBattery(Double)
    }

    private(set) var status: Status = .unavailable

    #if os(iOS) || os(visionOS)
    private var observationTokens: [NotificationCenter.ObservationToken] = []
    /// `isBatteryMonitoringEnabled` is process-wide, so it stays on until the last monitor
    /// stops. See CODE_AUDIT_23 §3.4.
    private(set) static var activeMonitorCount = 0
    #endif
    #if os(macOS)
    private var pollTask: Task<Void, Never>?
    /// macOS has no native battery-change notification (unlike `UIDevice`'s), so this polls
    /// instead. See CODE_AUDIT §9.14.
    private static let pollInterval: Duration = .seconds(30)
    #endif

    func startMonitoring() {
        refresh()
        #if os(iOS) || os(visionOS)
        guard observationTokens.isEmpty else { return }
        Self.activeMonitorCount += 1
        UIDevice.current.isBatteryMonitoringEnabled = true
        observationTokens = [
            NotificationCenter.default.addObserver(
                of: UIDevice.current,
                for: UIDevice.BatteryLevelDidChangeMessage.self
            ) { [weak self] _ in
                self?.refresh()
            },
            NotificationCenter.default.addObserver(
                of: UIDevice.current,
                for: UIDevice.BatteryStateDidChangeMessage.self
            ) { [weak self] _ in
                self?.refresh()
            }
        ]
        #elseif os(macOS)
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
        #endif
    }

    func stopMonitoring() {
        #if os(iOS) || os(visionOS)
        guard !observationTokens.isEmpty else { return }
        for token in observationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observationTokens.removeAll()
        Self.activeMonitorCount -= 1
        if Self.activeMonitorCount <= 0 {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
        #elseif os(macOS)
        pollTask?.cancel()
        pollTask = nil
        #endif
    }

    private func refresh() {
        #if os(iOS) || os(visionOS)
        let device = UIDevice.current
        switch device.batteryState {
        case .unplugged:
            status = device.batteryLevel >= 0 ? .onBattery(Double(device.batteryLevel)) : .unavailable
        case .charging, .full, .unknown:
            status = .unavailable
        @unknown default:
            status = .unavailable
        }
        #elseif os(macOS)
        status = Self.macBatteryStatus()
        #else
        status = .unavailable
        #endif
    }

    #if os(macOS)
    /// tvOS and most Macs have no battery at all; `kIOPSTypeKey` not matching
    /// `kIOPSInternalBatteryType` (desktop Macs, or a Mac laptop queried
    /// before the power source list is populated) also resolves to
    /// `.unavailable`, which is the correct "nothing to show" outcome.
    private static func macBatteryStatus() -> Status {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return .unavailable }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: AnyObject],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isOnACPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            guard !isCharging, !isOnACPower else { return .unavailable }

            guard let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maxCapacity = description[kIOPSMaxCapacityKey] as? Int,
                  maxCapacity > 0
            else { return .unavailable }
            return .onBattery(Double(currentCapacity) / Double(maxCapacity))
        }
        return .unavailable
    }
    #endif
}
