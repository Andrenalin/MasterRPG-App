// @copyright André Trettin

#if os(visionOS)
import Accelerate
import AVKit
import Combine
import RealityKit
import SwiftUI
//import Dice3dAssets

let dice3dAssetsBundle: Bundle? = nil

public struct DiceSpace: View {
    public init(root: DiceRoot) {
        self.root = root
        self._gestureModel =
         StateObject(wrappedValue: DiceHandTrackingGestureModel(diceRoot: root))
    }
    
    public static let immersiveSpaceId = "DiceSpace"

    let root: DiceRoot

    @StateObject private var gestureModel: DiceHandTrackingGestureModel

    var viewModel: DiceSpaceModel {
        root.diceSpaceModel
    }

    @State private var draggedEntity: Entity? = nil

    public var body: some View {
        @Bindable var viewModel = viewModel

        /*
         
         var windowSize = 24
         var vx1: [Double] = .init(repeating: 0, count: windowSize)
         var vy1: [Double] = .init(repeating: 0, count: windowSize)
         var vz1: [Double] = .init(repeating: 0, count: windowSize)
         var vw1: [Double] = .init(repeating: 0, count: windowSize)
         var wIndex = 0
         var lastHeartDetectionTime = Date.timeIntervalSinceReferenceDate

        RealityView { content, _  in
            // Add the initial RealityKit content
            if let entity = try? await Entity(named: "Dice20", in: dice3dAssetsBundle) {
                let rootEntity = Entity()
                viewModel.rootEntity = rootEntity
                content.add(rootEntity)
                viewModel.diceSixEntity = entity
                rootEntity.addChild(entity)
                viewModel.updateDice()
                viewModel.updateScale()
            }
        } update: { content, attachments  in
//            if let diceEntity = viewModel.diceSixEntity, let attachmentEntity = attachments.entity(for: "D6") {
//                content.add(attachmentEntity)
//                attachmentEntity.setPosition([0, 0.2, 0], relativeTo: diceEntity)
//            }


            let handsCenterTransform = gestureModel.computeTransformOfUserPerformedGrabingDiceGesture()
            if let handsCenter = handsCenterTransform {
                let position = Pose3D(handsCenter)!.position
                let rotation = Pose3D(handsCenter)!.rotation

                // Rolling average window of N, ~2-30 frames
                vx1[wIndex] = rotation.vector.x
                vy1[wIndex] = rotation.vector.y
                vz1[wIndex] = rotation.vector.z
                vw1[wIndex] = rotation.vector.w

                let averageX = vDSP.mean(vx1)
                let averageY = vDSP.mean(vy1)
                let averageZ = vDSP.mean(vz1)
                let averageW = vDSP.mean(vw1)

                wIndex += 1
                wIndex %= windowSize


                // change the dices??
                //beamIntermediate.transform.translation = SIMD3<Float>(position.vector)
                viewModel.diceSixEntity?.transform.rotation = simd_quatf(vector: [Float(averageX), Float(averageY), Float(averageZ), Float(averageW)])

                lastHeartDetectionTime = Date.timeIntervalSinceReferenceDate

                // Could be intertesting to send this to other players
                // in ortder to roll this dice on their Spcae too
//                if gameModel.isSharePlaying {
//                    sendBeamPositionUpdate(Pose3D(handsCenter)!)
//                }
            }


        } attachments: {
            // Labelling the dice.... but not needed
            Button {} label: {
                Label("6", systemImage: "dice")
            }
            .background(.green)
            .tag("D6")
        }
        .gesture(DragGesture(minimumDistance: 0.0)
            .targetedToAnyEntity()
            .onChanged { @MainActor drag in
                let entity = drag.entity
                guard entity[parentMatching: "Dice Six"] != nil || entity[parentMatching: "Dice Two"] != nil else { return }

                // Rotation
                let dragPoint = Point3D(drag.gestureValue.translation3D.vector) / 300
                let zRotation = (-180 * (dragPoint.x)).clamped(to: -180...180)
                let yRotation = (-180 * (dragPoint.y)).clamped(to: -180...180)

                let newOrientation = Rotation3D(angle: .degrees(Double(zRotation)), axis: .z)
                    .rotated(
                        by: .init(angle: .degrees(Double(yRotation)), axis: .x)
                    )

                let diceEntity = entity[parentMatching: "Dice Two"] != nil ? viewModel.diceTwoEntity : viewModel.diceSixEntity
                guard let diceEntity else { return }
                diceEntity.orientation = simd_quatf(newOrientation)

                // Move
                let newPosition = drag.convert(drag.location3D, from: .local, to: drag.entity.parent!)

                diceEntity.setPosition(newPosition, relativeTo: entity)
            }
            .onEnded { dragEnd in
                let diceEntity = dragEnd.entity[parentMatching: "Dice Two"] != nil ? viewModel.diceTwoEntity : viewModel.diceSixEntity

                guard let diceEntity else { return }
                print("*** orientation: \(diceEntity.orientation)")
                viewModel.rollDice(diceEntity: diceEntity)

                let newPosition = dragEnd.convert(dragEnd.gestureValue.predictedEndLocation3D, from: .local, to: dragEnd.entity.parent!)

                diceEntity.setPosition(newPosition, relativeTo: dragEnd.entity)
            }
        )
        .task {
            await gestureModel.start()
        }
        .task {
            await gestureModel.publishHandTrackingUpdates()
        }
        .task {
            await gestureModel.monitorSessionEvents()
        }
         */
    }
}

#Preview {
    DiceSpace(root: .preview)
}

#endif
