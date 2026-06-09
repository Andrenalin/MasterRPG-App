// @copyright André Trettin

#if !os(tvOS)
import RealityKit
import SpaceRPG

#if os(visionOS)
import DiceRPG
#endif

struct RealityKitInit {
    /// Registers all custom RealityKit components used in the app
    @MainActor static func registerRealityKitComponents() {
        // Register gesture component for interactive entities
        //GestureComponent.registerComponent()
        
#if os(visionOS)
        // Register dice rolling components and system
        DiceComponent.registerComponent()
        DiceRollSystem.registerSystem()
#endif
    }
}

#endif
