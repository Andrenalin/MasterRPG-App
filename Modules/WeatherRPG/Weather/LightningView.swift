//
//  LightningView.swift
//  Weather
//
//  Created by Paul Hudson on 17/03/2022.
//

import SwiftUI

struct LightningView: View {
    var frequency: Double = 0.0
    let maximumBolts: Int
    let forkProbability: Int
    let trigger: Int
    /// A strike another device shared; drawn as sent, at this view's width.
    let incomingBolt: LightningBoltSpec?
    /// Called with the strike a tap (or `trigger`) just started, so it can be shared.
    let onTap: ((LightningBoltSpec) -> Void)?
    /// Whether a tap strikes. Off for a player in a game: only the game master strikes.
    let isTapEnabled: Bool

    // Boxed in @State so in-flight bolts survive `WeatherViewer.body`
    // re-evaluations triggered by unrelated model changes instead of resetting
    // on every edit. `maximumBolts`/`forkProbability` are re-applied to the
    // persisted instance below since they're baked in only at construction.
    // See CODE_AUDIT_Weather §8.1.
    @State private var lightning: Lightning
    /// Whether a strike is running. The timeline is paused while none is: it used to redraw a
    /// full-screen transparent fill and two blur passes every frame of every idle game screen.
    /// See CODE_AUDIT_26 §7.20.
    @State private var isAnimating = false

    @Environment(\.accessibilityDimFlashingLights) private var accessibilityDimFlashingLights
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button(action: tap) {
            TimelineView(.animation(paused: shouldSuppressLightning || !isAnimating)) { timeline in
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
        // The canvas is transparent between strikes: the whole layer is the button's target.
        .contentShape(.rect)
        .allowsHitTesting(isTapEnabled)
        .accessibilityHidden(true)
        #if os(tvOS)
        // Hidden from accessibility, so it must not take focus either: on Apple TV the focus
        // engine could land on this invisible full-screen control. See CODE_AUDIT_20 §8.8.
        // Not elsewhere: on visionOS an unfocusable control takes no gaze and pinch.
        .focusable(false)
        #endif
        .ignoresSafeArea()
        .background {
            // Periodic auto-strike cadence, replacing a `Timer.publish`/Combine
            // subscription with manual cancel-and-republish bookkeeping to
            // change the interval. `frequency < 1` means "off" — no periodic
            // trigger at all (matches the previous `timer.upstream.connect().cancel()`
            // behavior). See CODE_AUDIT_9 §4.2.
            if frequency >= 1 {
                PeriodicStrikeTrigger(interval: 60.0 / frequency) { strike() }
            }
        }
        // Ends the animation once the strike has faded. The check is coarse on purpose: the last
        // frame drawn is the cleared one.
        .task(id: isAnimating) {
            guard isAnimating else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                if lightning.isIdle {
                    isAnimating = false
                    return
                }
            }
        }
        .onChange(of: trigger) {
            tap()
        }
        .onChange(of: incomingBolt) { _, incomingBolt in
            guard let incomingBolt else { return }
            strike(incomingBolt)
        }
        .onChange(of: shouldSuppressLightning) { _, shouldSuppressLightning in
            if shouldSuppressLightning {
                lightning.stop()
            }
        }
        .onChange(of: maximumBolts, initial: true) { _, newValue in
            lightning.maximumBolts = newValue
        }
        .onChange(of: forkProbability, initial: true) { _, newValue in
            lightning.forkProbability = newValue
        }
    }

    init(
        frequency: Double = 0.0,
        maximumBolts: Int = 4,
        forkProbability: Int = 20,
        trigger: Int = 0,
        incomingBolt: LightningBoltSpec? = nil,
        onTap: ((LightningBoltSpec) -> Void)? = nil,
        isTapEnabled: Bool = true
    ) {
        self.frequency = frequency
        self.maximumBolts = maximumBolts
        self.forkProbability = forkProbability
        self.trigger = trigger
        self.incomingBolt = incomingBolt
        self.onTap = onTap
        self.isTapEnabled = isTapEnabled
        _lightning = State(initialValue: Lightning(maximumBolts: maximumBolts, forkProbability: forkProbability))
    }

    private var shouldSuppressLightning: Bool {
        accessibilityReduceMotion || accessibilityDimFlashingLights
    }

    /// A strike that starts on its own (the periodic cadence) or arrives from another device.
    private func strike(_ spec: LightningBoltSpec = .random()) {
        guard !shouldSuppressLightning else { return }
        if lightning.strike(spec) {
            isAnimating = true
        }
    }

    /// A strike the user asked for. It is shared when it starts here, or when this device
    /// suppresses flashing: the receiving devices apply their own accessibility settings, and
    /// a game master's setting must not take the strike away from the players.
    private func tap() {
        let spec = LightningBoltSpec.random()
        if shouldSuppressLightning {
            onTap?(spec)
        } else if lightning.strike(spec) {
            isAnimating = true
            onTap?(spec)
        }
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
