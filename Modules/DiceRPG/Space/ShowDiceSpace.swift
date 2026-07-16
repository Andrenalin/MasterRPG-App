// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import SwiftUI

struct ShowDiceSpace: View {
    let root: DiceRootModel
    let itemId: UUID?

    var viewModel: DiceSpaceModel

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor
    var areControlsShowing: Bool {
        viewModel.rootEntity != nil && viewModel.showImmersiveContent
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        
        VStack {
            Toggle(isOn: $viewModel.showImmersiveContent) {
                Label { Text("Show Dice in Space", bundle: .module) } icon: { Image(systemName: "dice") }
            }
            .onChange(of: viewModel.showImmersiveContent) {
                Task {
                    if viewModel.showImmersiveContent {
                        await root.gameController.focus(on: itemId)
                        viewModel.reset()
                        await openImmersiveSpace(id: DiceSpace.immersiveSpaceId)
                    } else {
                        await dismissImmersiveSpace()
                    }
                }
            }

            if areControlsShowing {
                HStack { Text("Scale", bundle: .module)
                    Slider(value: $viewModel.contentScaleSliderValue)
                        .accessibilityLabel(Text("Dice scale", bundle: .module))
                        .accessibilityValue(
                            Text(
                                Double(viewModel.contentScaleSliderValue),
                                format: .percent.precision(.fractionLength(0))
                            )
                        )
                        .onChange(of: viewModel.contentScaleSliderValue) { _, _ in
                            viewModel.updateScale()
                        }
                }

                Toggle(isOn: $viewModel.twoDice) {
                    Label { Text("Show 2nd D20", bundle: .module) } icon: { Image(systemName: "dice") }
                }
                .onChange(of: viewModel.twoDice) { _, _ in
                    Task {
                        await viewModel.switchDice()
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .default, value: areControlsShowing)
    }

}

#Preview {
    ShowDiceSpace(root: .preview, itemId: DiceModel.previewId, viewModel: DiceSpaceModel())
}

#endif
