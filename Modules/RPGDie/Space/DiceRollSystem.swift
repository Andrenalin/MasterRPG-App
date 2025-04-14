// @copyright André Trettin

#if os(visionOS)

import Foundation
import RealityKit
//import Dice3dAssets

/// This system is used to update the dice component with the new result for each role.
/// The idea is that also the player dice from the other player will be shown in the space not only it's own dice.
///  At moment I don't know what I need.. so this is a placeholder for later
class DiceRoolSystem: System {

    // This must be called in the init
    // DiceRoolSystem.registerSystem()

    //private static let diceQuery = EntityQuery(where: .has(DiceComponent.self))

    // this could be interesting.... at the moment I don't have a concrete use case
//    static var dependencies: [SystemDependency] {
//            [.after(SystemA.self),        // Run SystemB after SystemA.
//             .before(SystemC.self)]       // Run SystemB before SystemC.
//    }

    required init(scene: Scene) {}

//    func update(context: SceneUpdateContext) {
//        context.scene.performQuery(Self.diceQuery).forEach { entity in
//            // Make per-frame changes to each dice entity here.
//        }
//    }
}

#endif
