//
//  LightningView.swift
//  Weather
//
//  Created by Paul Hudson on 17/03/2022.
//

import SwiftUI

struct LightningView: View {
    var frequency: Double = 0.0
    var lightning: Lightning
    let trigger: Int

    @Environment(\.accessibilityDimFlashingLights) private var accessibilityDimFlashingLights
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button(action: strike) {
            TimelineView(.animation(paused: shouldSuppressLightning)) { timeline in
                Canvas { context, size in
                    guard !shouldSuppressLightning else { return }

                    lightning.update(date: timeline.date, in: size)

                    let fullScreen = Path(CGRect(origin: .zero, size: size))
                    context.fill(fullScreen, with: .color(.white.opacity(lightning.flashOpacity)))

                    for _ in 0 ..< 2 {
                        for bolt in lightning.bolts {
                            var path = Path()
                            path.addLines(bolt.points)
                            context.stroke(path, with: .color(.white), lineWidth: bolt.width)
                        }

                        context.addFilter(.blur(radius: 5))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
        .ignoresSafeArea()
        .background {
            // Periodic auto-strike cadence, replacing a `Timer.publish`/Combine
            // subscription with manual cancel-and-republish bookkeeping to
            // change the interval. `frequency < 1` means "off" — no periodic
            // trigger at all (matches the previous `timer.upstream.connect().cancel()`
            // behavior). See CODE_AUDIT_9 §4.2.
            if frequency >= 1 {
                PeriodicStrikeTrigger(interval: 60.0 / frequency, action: strike)
            }
        }
        .onChange(of: trigger) {
            strike()
        }
        .onChange(of: shouldSuppressLightning) { _, shouldSuppressLightning in
            if shouldSuppressLightning {
                lightning.stop()
            }
        }
    }

    init(
        frequency: Double = 0.0,
        maximumBolts: Int = 4,
        forkProbability: Int = 20,
        trigger: Int = 0
    ) {
        lightning = Lightning(maximumBolts: maximumBolts, forkProbability: forkProbability)
        self.frequency = frequency
        self.trigger = trigger
    }

    private var shouldSuppressLightning: Bool {
        accessibilityReduceMotion || accessibilityDimFlashingLights
    }

    private func strike() {
        guard !shouldSuppressLightning else { return }
        lightning.strike()
    }
}

/// Invisible view that fires `action` once per tick of a `TimelineView.periodic`
/// schedule — the `TimelineView` equivalent of a repeating `Timer`/Combine
/// subscription, with no manual connect/cancel bookkeeping needed to change the
/// interval (a new `interval` simply produces a new schedule). See CODE_AUDIT_9 §4.2.
private struct PeriodicStrikeTrigger: View {
    let interval: TimeInterval
    let action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { timeline in
            Color.clear
                .onChange(of: timeline.date, initial: false) { _, _ in
                    action()
                }
        }
    }
}

#Preview {
    LightningView(frequency: 60.0, maximumBolts: 60, forkProbability: 100)
        .background(.black)
}
