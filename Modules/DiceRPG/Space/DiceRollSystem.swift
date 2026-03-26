// @copyright André Trettin

#if os(visionOS)

import Foundation
import RealityKit

/// Component that holds the state of a dice roll
public struct DiceComponent: Component {
    /// The result of the dice roll (1-20 for d20, 1-6 for d6, etc.)
    public var result: Int

    /// Whether the dice is currently animating to its final orientation
    public var isRolling: Bool

    /// The target orientation the dice should animate to
    public var targetOrientation: simd_quatf

    /// The type of dice (d6, d20, etc.)
    public var diceType: DiceType

    /// Animation progress (0.0 to 1.0)
    public var animationProgress: Float

    public enum DiceType: String, Codable {
        case d6 = "Dice Six"
        case d20 = "Dice Two"
    }

    public init(result: Int = 1, isRolling: Bool = false, targetOrientation: simd_quatf = simd_quatf(real: 1, imag: .zero), diceType: DiceType = .d20, animationProgress: Float = 1.0) {
        self.result = result
        self.isRolling = isRolling
        self.targetOrientation = targetOrientation
        self.diceType = diceType
        self.animationProgress = animationProgress
    }
}

/// System that animates dice to their final roll result orientation
public class DiceRollSystem: System {

    private static let diceQuery = EntityQuery(where: .has(DiceComponent.self))

    /// Animation speed multiplier
    private let animationSpeed: Float = 5.0

    public required init(scene: Scene) {}

    public func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.diceQuery, updatingSystemWhen: .rendering) {
            guard var diceComponent = entity.components[DiceComponent.self] else { continue }

            // Only animate if the dice is rolling
            guard diceComponent.isRolling else { continue }

            // Update animation progress
            diceComponent.animationProgress += Float(context.deltaTime) * animationSpeed

            if diceComponent.animationProgress >= 1.0 {
                // Animation complete - snap to final orientation
                entity.orientation = diceComponent.targetOrientation
                diceComponent.isRolling = false
                diceComponent.animationProgress = 1.0
            } else {
                // Smoothly interpolate to target orientation using spherical linear interpolation
                entity.orientation = simd_slerp(
                    entity.orientation,
                    diceComponent.targetOrientation,
                    Float(context.deltaTime) * animationSpeed
                )
            }

            // Update the component back to the entity
            entity.components.set(diceComponent)
        }
    }
}

#endif
