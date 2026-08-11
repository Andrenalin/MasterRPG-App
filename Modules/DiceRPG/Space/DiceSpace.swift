// @copyright André Trettin

#if os(visionOS)
import Accelerate
import AVKit
import Combine
import os.log
import RealityKit
import SwiftUI
//import Dice3dAssets

let dice3dAssetsBundle: Bundle? = nil

public struct DiceSpace: View {
    public init(root: DiceRootModel) {
        self.root = root
        self._gestureModel = State(wrappedValue: DiceHandTrackingGestureModel(diceRoot: root))
    }

    public static let immersiveSpaceId = "DiceSpace"

    let root: DiceRootModel

    @State private var gestureModel: DiceHandTrackingGestureModel

    var viewModel: DiceSpaceModel {
        root.diceSpaceModel
    }

    @State private var draggedEntity: Entity? = nil

    public var body: some View {
        @Bindable var viewModel = viewModel

        RealityView { content in
            do {
                // Load the dice entity asynchronously
                guard let entity = try? await Entity(named: "Dice20", in: dice3dAssetsBundle) else {
                    Logger.diceSpace.error("Failed to load Dice20 entity")
                    return
                }

                let rootEntity = Entity()
                viewModel.rootEntity = rootEntity
                content.add(rootEntity)
                viewModel.diceSixEntity = entity
                rootEntity.addChild(entity)
                viewModel.updateDice()
                viewModel.updateScale()
            }
//        } update: { content, attachments in
//            // Update logic can be added here if needed
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
                viewModel.rollDice(diceEntity: diceEntity)

                let newPosition = dragEnd.convert(dragEnd.gestureValue.predictedEndLocation3D, from: .local, to: dragEnd.entity.parent!)
                diceEntity.setPosition(newPosition, relativeTo: dragEnd.entity)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Dice space", bundle: .module))
        .accessibilityAction(named: Text("Roll first die", bundle: .module)) {
            guard let dice = viewModel.diceSixEntity else { return }
            viewModel.rollDice(diceEntity: dice)
        }
        .accessibilityAction(named: Text("Roll second die", bundle: .module)) {
            guard let dice = viewModel.diceTwoEntity else { return }
            viewModel.rollDice(diceEntity: dice)
        }
        .task {
            await gestureModel.start()
        }
        .task {
            await gestureModel.publishHandTrackingUpdates()
        }
        .task {
            await gestureModel.monitorSessionEvents()
        }
    }
}

#Preview {
    DiceSpace(root: .preview)
}

#endif
