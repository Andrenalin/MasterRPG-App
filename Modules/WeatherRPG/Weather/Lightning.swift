//
//  Lightning.swift
//  Weather
//
//  Created by Paul Hudson on 17/03/2022.
//

import SwiftUI

/// A small seedable generator, so a bolt shared with another device grows with the same random
/// jitter and forks as on the device that struck it.
struct LightningRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// SplitMix64.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// One lightning strike as every device draws it: where the main bolt starts across the width,
/// and the seed of its random shape. `id` tells two identical strikes apart for `onChange`.
struct LightningBoltSpec: Equatable, Sendable {
    let id = UUID()
    /// The start position across the view, from 0 (left) to 1 (right).
    let startFraction: Double
    let seed: UInt64

    init(startFraction: Double, seed: UInt64) {
        self.startFraction = startFraction.isFinite ? min(max(startFraction, 0), 1) : 0.5
        self.seed = seed
    }

    static func random() -> LightningBoltSpec {
        LightningBoltSpec(startFraction: .random(in: 0 ... 1), seed: .random(in: .min ... .max))
    }
}

class Lightning {
    enum LightningState {
        case waiting, preparing, striking, fading
    }

    /// Points added per update tick, scaled by elapsed time. See CODE_AUDIT_Weather §9.14.
    private static let boltGrowthSpeed = 800.0
    /// Random horizontal/vertical wobble added to each growth step.
    private static let jitterRange = -10.0 ... 10.0
    /// Random spread applied around straight-down when a bolt forks.
    private static let forkAngleSpread = Double.pi / 4
    /// Screen-flash opacity set the instant a strike finishes.
    private static let strikeFlashOpacity = 0.6
    /// Bolt width multiplier applied once a strike finishes, before fading.
    private static let strikeWidthGrowth = 1.5
    /// Bolt width lost per second while fading out.
    private static let fadeRate = 15.0

    /// Where a bolt may start: 50 pt in from both edges, or the middle of a view narrower than
    /// 100 pt, where `50 ... width - 50` would be an invalid range and trap. See CODE_AUDIT_22 §5.12.
    static func boltStartRange(width: CGFloat) -> ClosedRange<Double> {
        let inset = 50.0
        guard width.isFinite, width > inset * 2 else {
            let middle = width.isFinite ? max(width, 0) / 2 : 0
            return middle ... middle
        }
        return inset ... Double(width) - inset
    }

    var bolts = [LightningBolt]()
    var state = LightningState.waiting
    var lastUpdate = Date.now
    var flashOpacity = 0.0

    /// No strike is running and nothing is left to draw.
    var isIdle: Bool { state == .waiting }

    /// The strike being prepared or drawn. Its seed drives the bolt's jitter and forks.
    private var spec = LightningBoltSpec.random()
    private var random = LightningRandom(seed: 0)

    var maximumBolts: Int
    var forkProbability: Int

    init(maximumBolts: Int, forkProbability: Int) {
        self.maximumBolts = maximumBolts
        self.forkProbability = forkProbability
    }

    func update(date: Date, in size: CGSize) {
        let delta = date.timeIntervalSince1970 - lastUpdate.timeIntervalSince1970
        lastUpdate = date

        switch state {
        case .waiting:
            break

        case .preparing:
            let range = Self.boltStartRange(width: size.width)
            let startPosition = CGPoint(x: range.lowerBound + spec.startFraction * (range.upperBound - range.lowerBound), y: 0)
            let newBolt = LightningBolt(start: startPosition, width: 5, angle: Angle.degrees(270).radians)
            bolts.append(newBolt)
            state = .striking

        case .striking:
            let speed = delta * Self.boltGrowthSpeed
            var hasFinishedStriking = true

            for bolt in bolts {
                guard var lastPoint = bolt.points.last else { continue }

                for _ in 0 ..< 5 {
                    let endX = lastPoint.x + (speed * cos(bolt.angle) + Double.random(in: Self.jitterRange, using: &random))
                    let endY = lastPoint.y - (speed * sin(bolt.angle) + Double.random(in: Self.jitterRange, using: &random))
                    lastPoint = CGPoint(x: endX, y: endY)
                    bolt.points.append(lastPoint)
                }

                if lastPoint.y < size.height {
                    hasFinishedStriking = false

                    if bolts.count < maximumBolts, Int.random(in: 0 ..< 100, using: &random) < forkProbability {
                        let newAngle = Double.random(in: -Self.forkAngleSpread ... Self.forkAngleSpread, using: &random) - .pi / 2
                        let newBolt = LightningBolt(start: lastPoint, width: bolt.width * 0.75, angle: newAngle)
                        bolts.append(newBolt)
                    }
                }
            }

            if hasFinishedStriking {
                state = .fading
                flashOpacity = Self.strikeFlashOpacity

                for bolt in bolts {
                    bolt.width *= Self.strikeWidthGrowth
                }
            }

        case .fading:
            var allFaded = true
            flashOpacity -= delta

            for bolt in bolts {
                bolt.width -= delta * Self.fadeRate

                if bolt.width > 0.05 {
                    allFaded = false
                }
            }

            if allFaded, flashOpacity <= 0 {
                state = .waiting
                bolts.removeAll(keepingCapacity: true)
            }
        }
    }

    /// Starts a strike unless one is already running. Returns whether it started.
    @discardableResult
    func strike(_ spec: LightningBoltSpec = .random()) -> Bool {
        guard state == .waiting else { return false }
        self.spec = spec
        random = LightningRandom(seed: spec.seed)
        state = .preparing
        return true
    }

    func stop() {
        state = .waiting
        bolts.removeAll(keepingCapacity: true)
        flashOpacity = 0
        lastUpdate = .now
    }
}
