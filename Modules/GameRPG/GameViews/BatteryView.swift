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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Group {
            if case let .onBattery(level) = monitor.status {
                Label {
                    Text(level, format: .percent.precision(.fractionLength(0)))
                } icon: {
                    Image(systemName: Self.symbolName(for: level))
                        .symbolEffect(.pulse, options: .repeating, isActive: level < 0.05 && !reduceMotion)
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
        //
        // `stopMonitoring()`/`startMonitoring()` are called from here rather than
        // `BatteryMonitor.deinit` — a `deinit` on a `@MainActor` class runs
        // nonisolated on this toolchain and can't touch actor-isolated state, so it
        // can't reach the notification observers / poll `Task` it would need to
        // cancel. `.onDisappear` reliably fires before the owning view (and its
        // `@State` `monitor`) is torn down, closing the leak described in
        // CODE_AUDIT §5.5 without requiring isolated deinit. Monitoring starts only here, never in
        // `BatteryMonitor.init`; see CODE_AUDIT_22 §3.1.
        .onAppear { monitor.startMonitoring() }
        .onDisappear { monitor.stopMonitoring() }
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

#Preview {
    BatteryView()
}
