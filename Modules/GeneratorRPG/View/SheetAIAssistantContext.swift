// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI
import FoundationModels

public extension View {
    func sheetAIAssistant(
        generatorRoot: GeneratorRootModel?,
        rootModel: SheetRootModel?,
        module: NetworkModules
    ) -> some View {
        overlay(alignment: .bottomTrailing) {
            if let rootModel, let generatorController = generatorRoot?.generatorControllers[module], generatorController.availblity {
                SheetAIAssistantContent(generatorController: generatorController, rootModel: rootModel)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }
}

/// The one assistant presentation attached to a parent detail or game screen.
///
/// iPhone publishes one control to the native tab accessory; larger platforms
/// render one control at the parent screen's bottom edge.
struct SheetAIAssistantContent: View {
    let generatorController: GeneratorController
    let rootModel: SheetRootModel

    var body: some View {
        GlassEffectContainerAll {
            SheetAIAssistantOverlayView(
                generatorController: generatorController,
                rootModel: rootModel
            )
        }
    }
}
#endif
