// @copyright André Trettin

import CoreRPG
import Observation
import SwiftUI

#if os(iOS) || os(visionOS)
import UIKit
#endif
#if os(macOS)
import IOKit.ps
#endif

/// Compact battery status icon for the game menu / toolbar. Hidden whenever
/// the device is charging, on battery-full, or on a platform where the
/// battery level can't be determined (tvOS, or a Mac without a battery).
struct BatteryView: View {
    @State private var monitor = BatteryMonitor()

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Group {
            if case let .onBattery(level) = monitor.status {
                Label {
                    Text(level, format: .percent.precision(.fractionLength(0)))
                } icon: {
                    Image(systemName: Self.symbolName(for: level))
                        .symbolEffect(.pulse, options: .repeating, isActive: level < 0.05)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(Self.color(for: level))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Battery", bundle: .module))
                .accessibilityValue(Text(level, format: .percent.precision(.fractionLength(0))))
            }
        }
        // Attached to the always-present wrapper, not the conditional content
        // above: monitoring must start regardless of the current status, since
        // the status starts `.unavailable` and only becomes `.onBattery` as a
        // *result* of monitoring running at least once.
    }

    private static func symbolName(for level: Double) -> String {
        switch level {
        case ..<0.125: "battery.0percent"
        case ..<0.375: "battery.25percent"
        case ..<0.625: "battery.50percent"
        case ..<0.875: "battery.75percent"
        default: "battery.100percent"
        }
    }

    private static func color(for level: Double) -> Color {
        if level <= 0.10 {
            .red
        } else if level <= 0.20 {
            .orange
        } else {
            .green
        }
    }
}

/// Watches the system battery, where available, and reduces it to the one
/// state this view cares about: the discharging level, or nothing to show.
/// Charging, full, and platforms without a queryable battery (tvOS, most
/// Macs) all collapse to `.unavailable` so the icon disappears rather than
/// showing a stale or meaningless reading.
@MainActor
@Observable
final class BatteryMonitor {
    init() {
        startMonitoring()
    }
    
    enum Status: Equatable, Sendable {
        case unavailable
        case onBattery(Double)
    }

    private(set) var status: Status = .unavailable

    #if os(iOS) || os(visionOS)
    private var observationTokens: [NotificationCenter.ObservationToken] = []
    #endif
    #if os(macOS)
    private var pollTask: Task<Void, Never>?
    #endif

    func startMonitoring() {
        refresh()
        #if os(iOS) || os(visionOS)
        guard observationTokens.isEmpty else { return }
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
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
        #endif
    }

    func stopMonitoring() {
        #if os(iOS) || os(visionOS)
        for token in observationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observationTokens.removeAll()
        UIDevice.current.isBatteryMonitoringEnabled = false
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

#Preview {
    BatteryView()
}
