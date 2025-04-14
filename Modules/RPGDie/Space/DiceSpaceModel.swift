// @copyright André Trettin

#if os(visionOS)
import ARKit
//import Dice3dAssets
import Foundation
import Observation
import RealityKit
import SwiftUI

@Observable 
final class DiceSpaceModel: @unchecked Sendable {
    
    /// This is the first dice we will show
    @MainActor
    var rootEntity: Entity? = nil
    /// How large will be the dice
    var contentScaleSliderValue: Float = 0.5
    // is the dice in the space visible
    var showImmersiveContent: Bool = false

    // 2nd dice
    @MainActor var twoDice: Bool = false

    @MainActor var diceSixEntity: Entity? = nil
    @MainActor var diceTwoEntity: Entity? = nil

    init() {}

    func reset() {}

    @MainActor
    func loadResources() async {
        diceSixEntity = await Self.loadFromRealityComposerPro(named: BundleAssets.diceSixEntity, fromSceneNamed: BundleAssets.diceSixScene)
        updateDice()
    }

    @MainActor
    func switchDice() async {
        if twoDice {
            guard let entity = try? await Entity(named: "Dice20", in: dice3dAssetsBundle) else { return }
            rootEntity?.addChild(entity)
            diceTwoEntity = entity
            updateTwoDice()
            updateScale()
        } else {
            guard let diceTwoEntity else { return }
            rootEntity?.removeChild(diceTwoEntity)
            self.diceTwoEntity = nil
        }
    }

    @MainActor
    func updateTwoDice() {
        diceTwoEntity?.name = "Dice Two"
        diceTwoEntity?.generateCollisionShapes(recursive: true)
        diceTwoEntity?.position = .init(x: 0.0, y: 0.0, z: -1.7)
        diceTwoEntity?.scale *= 0.05
        diceTwoEntity?.components[InputTargetComponent.self] = InputTargetComponent(allowedInputTypes: .all)
    }

    @MainActor
    func updateDice() {
        diceSixEntity?.name = "Dice Six"
        diceSixEntity?.generateCollisionShapes(recursive: true)
        diceSixEntity?.position = .init(x: 0, y: 0.0, z: -1.7)
        diceSixEntity?.scale *= 0.05
        diceSixEntity?.components[InputTargetComponent.self] = InputTargetComponent(allowedInputTypes: .all)
    }

    @MainActor
    func updateScale() {
        let newScale = Float.lerp(a: 0.01, b: 0.1, t: contentScaleSliderValue)
        diceSixEntity?.setScale(SIMD3<Float>(repeating: newScale), relativeTo: nil)
        guard let diceSixEntity else { return }
        diceTwoEntity?.scale = diceSixEntity.scale
    }

    @MainActor
    func rollDice(diceEntity: Entity) {

        let result = RawDie.twenty.role()
        print("*** Dicde result = \(result)")
        //diceEntity.components[DiceComponent.self] = DiceComponent(result: result)
        let orientation = DiceSpaceModel.dice20OrientationMap[result, default: simd_quatf(real: 1, imag: SIMD3<Float>(0, 0, 0))]

        diceEntity.orientation = orientation
    }

    static let dice20OrientationMap = [
        1: simd_quatf(real: 1.0, imag: SIMD3<Float>(0.0, 0.0, 0.0)),
        2: simd_quatf(real: 0.9287174, imag: SIMD3<Float>(0.21577685, -0.06824095, 0.29371342)),
        3: simd_quatf(real: 0.0034936722, imag: SIMD3<Float>(-0.77532077, 0.63155156, 0.002845834)),
        4: simd_quatf(real: 0.72552866, imag: SIMD3<Float>(-0.35071597, 0.25769827, 0.53310233)),
        5: simd_quatf(real: 0.5985438, imag: SIMD3<Float>(0.10063257, -0.13177012, 0.7837442)),
        6: simd_quatf(real: 0.7458715, imag: SIMD3<Float>(-0.30524242, -0.22423425, -0.547925)),
        7: simd_quatf(real: 5.2236128e-17, imag: SIMD3<Float>(3.194975e-17, -0.521779, 0.8530807)),
        8: simd_quatf(real: 0.93297076, imag: SIMD3<Float>(0.057653528, 0.021914493, -0.35462847)),
        9: simd_quatf(real: 0.49630105, imag: SIMD3<Float>(-0.8036619, 0.27937058, 0.1725252)),
        10: simd_quatf(real: 0.81138873, imag: SIMD3<Float>(0.46918184, 0.17449877, -0.30177283)),
        11: simd_quatf(real: 0.3560689, imag: SIMD3<Float>(-0.16403137, 0.38491654, 0.83555245)),
        12: simd_quatf(real: 0.7933829, imag: SIMD3<Float>(0.51257265, -0.17818154, 0.2757974)),
        13: simd_quatf(real: 0.35196403, imag: SIMD3<Float>(-0.019562457, 0.0519329, 0.93436694)),
        14: simd_quatf(real: 0.8875431, imag: SIMD3<Float>(-0.45624897, -0.029289167, -0.056976344)),
        15: simd_quatf(real: 0.51597655, imag: SIMD3<Float>(0.28570303, -0.39118743, 0.70648026)),
        16: simd_quatf(real: 0.7961112, imag: SIMD3<Float>(-0.04424853, -0.03349304, -0.6026004)),
        17:simd_quatf(real: 0.51770544, imag: SIMD3<Float>(0.28255814, 0.38688144, -0.70884746)),
        18: simd_quatf(real: 0.8052997, imag: SIMD3<Float>(-0.029764028, 0.021869944, 0.5917163)),
        19: simd_quatf(real: 0.114027925, imag: SIMD3<Float>(-0.93280655, 0.339336, 0.041481037)),
        20: simd_quatf(real: 1.0, imag: SIMD3<Float>(0.0, 0.0, 0.0))
    ]

    // constant / global settings
    struct BundleAssets {
        static let
        diceSixScene = "Dice6.usda",
        diceSixEntity = "Dice6",
        diceTwentyScene = "Dice20.usda",
        diceTwentyEntity = "Dice20"
    }

    @MainActor
    static let spaceOrigin = Entity()
    @MainActor
    static let cameraAnchor = AnchorEntity(.head)

    @MainActor
    static func loadFromRealityComposerPro(named entityName: String, fromSceneNamed sceneName: String) async -> Entity? {
        var entity: Entity? = nil
        do {
            let scene = try await Entity(named: sceneName, in: dice3dAssetsBundle)
            entity = scene.findEntity(named: entityName)
        } catch {
            print("Error loading \(entityName) from scene \(sceneName): \(error.localizedDescription)")
        }
        return entity
    }


    var entityMap: [UUID: Entity] = [:]

    @MainActor
    func updatePlane(_ anchor: PlaneAnchor) {
        if entityMap[anchor.id] == nil {
            print("**** Have plane")
            // Add a new entity to represent this plane.
            let entity = ModelEntity(
                mesh: .generateText(anchor.classification.description)
            )
            entityMap[anchor.id] = entity
            rootEntity?.addChild(entity)
        }

        /*
        guard let rootEntity else {
            return
        }
        print("*** - \(anchor.transform)")
        entityMap[anchor.id]?.setTransformMatrix(anchor.transform, relativeTo: rootEntity)
         */
    }

    @MainActor
    func removePlane(_ anchor: PlaneAnchor) {
        entityMap[anchor.id]?.removeFromParent()
        entityMap.removeValue(forKey: anchor.id)
    }
}

public extension FloatingPoint {
    static func lerp(a: Self, b: Self, t: Self) -> Self {
        let one = Self(1)
        let oneMinusT = one - t
        let aTimesOneMinusT = a * oneMinusT
        let bTimesT = b * t
        return aTimesOneMinusT + bTimesT
    }
}

extension Entity {
    /// Property for getting or setting an entity's `modelComponent`.
    var modelComponent: ModelComponent? {
        get { components[ModelComponent.self] }
        set { components[ModelComponent.self] = newValue }
    }

    var descendentsWithModelComponent: [Entity] {
        var descendents = [Entity]()

        for child in children {
            if child.components[ModelComponent.self] != nil {
                descendents.append(child)
            }
            descendents.append(contentsOf: child.descendentsWithModelComponent)
        }
        return descendents
    }
}

extension Entity {
    func setMaterialParameterValues(parameter: String, value: MaterialParameters.Value) {
        let modelEntities = descendentsWithModelComponent
        for entity in modelEntities {
            if var modelComponent = entity.modelComponent {

                modelComponent.materials = modelComponent.materials.map {

                    guard var material = $0 as? ShaderGraphMaterial else { return $0 }
                    if material.parameterNames.contains(parameter) {
                        do {
                            try material.setParameter(name: parameter, value: value)
                        } catch {
                            print("Error setting parameter: \(error.localizedDescription)")
                        }
                    }
                    return material
                }
                entity.modelComponent = modelComponent
            }
        }
    }

    subscript(parentMatching targetName: String) -> Entity? {
        if name.contains(targetName) {
            return self
        }

        guard let nextParent = parent else {
            return nil
        }

        return nextParent[parentMatching: targetName]
    }

    func getParent(nameBeginsWith name: String) -> Entity? {
        if self.name.hasPrefix(name) {
            return self
        }
        guard let nextParent = parent else {
            return nil
        }

        return nextParent.getParent(nameBeginsWith: name)
    }

    func getParent(withName name: String) -> Entity? {
        if self.name == name {
            return self
        }
        guard let nextParent = parent else {
            return nil
        }

        return nextParent.getParent(withName: name)
    }

    subscript(descendentMatching targetName: String) -> Entity? {
        if name.contains(targetName) {
            return self
        }

        var match: Entity? = nil
        for child in children {
            match = child[descendentMatching: targetName]
            if let match = match {
                return match
            }
        }

        return match
    }

    func getSelfOrDescendent(withName name: String) -> Entity? {
        if self.name == name {
            return self
        }
        var match: Entity? = nil
        for child in children {
            match = child.getSelfOrDescendent(withName: name)
            if match != nil {
                return match
            }
        }

        return match
    }

    func forward(relativeTo referenceEntity: Entity?) -> SIMD3<Float> {
        normalize(convert(direction: SIMD3<Float>(0, 0, +1), to: referenceEntity))
    }

    var forward: SIMD3<Float> {
        forward(relativeTo: nil)
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension SIMD4 {
    var xyz: SIMD3<Scalar> {
        self[SIMD3(0, 1, 2)]
    }
}

@Observable
final class AttachmentsProvider {

    var attachments: [ObjectIdentifier: AnyView] = [:]

    var sortedTagViewPairs: [(tag: ObjectIdentifier, view: AnyView)] {
        attachments.map { key, value in
            (tag: key, view: value)
        }.sorted { $0.tag < $1.tag }
    }
}

#endif
