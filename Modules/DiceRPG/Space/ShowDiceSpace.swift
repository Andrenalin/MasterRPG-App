// @copyright André Trettin

#if os(visionOS)
import AndrenalinKit
import SwiftUI

struct ShowDiceSpace: View {
    let root: DiceRootModel
    let itemId: UUID?

    var viewModel: DiceSpaceModel

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    @MainActor
    var areControlsShowing: Bool {
        viewModel.rootEntity != nil && viewModel.showImmersiveContent
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        
        VStack {
            Toggle(isOn: $viewModel.showImmersiveContent) {
                Label("Show Dice in Space", systemImage: "dice")
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
                HStack { Text("Scale")
                    Slider(value: $viewModel.contentScaleSliderValue)
                        .onChange(of: viewModel.contentScaleSliderValue) { _, _ in
                            viewModel.updateScale()
                        }
                }

                Toggle(isOn: $viewModel.twoDice) {
                    Label("Show 2nd D20", systemImage: "dice")
                }
                .onChange(of: viewModel.twoDice) { _, _ in
                    Task {
                        await viewModel.switchDice()
                    }
                }
            }
        }
        .animation(.default, value: areControlsShowing)
    }

}

#Preview {
    ShowDiceSpace(root: .preview, itemId: DiceModel.previewId, viewModel: DiceSpaceModel())
}

#endif
